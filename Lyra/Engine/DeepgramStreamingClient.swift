import Foundation

/// Assembles Deepgram's incremental results into displayable text.
///
/// The v2 (Flux) protocol is turn-based: while the speaker is mid-turn, each
/// message carries the *whole* hypothesis for that turn so far, revised as more
/// audio arrives — so a message replaces the previous text for its turn rather
/// than extending it. `EndOfTurn` settles the turn, and the next `turn_index`
/// starts a new one. Appending every message would repeat most of the words.
///
/// Also accepts the older v1 shape (`channel.alternatives[].transcript` with
/// `is_final`), so pointing the endpoint at v1 degrades instead of going silent.
///
/// Pure and value-typed so the assembly rules are unit-testable without a socket.
struct DeepgramTranscriptAssembler: Equatable {
    /// Turns Deepgram has settled and will not revise.
    private(set) var committed: String = ""
    /// The turn currently being revised.
    private(set) var currentTurn: String = ""
    private var currentTurnIndex: Int?

    /// Everything to display: settled turns plus the live one.
    var text: String {
        if committed.isEmpty { return currentTurn }
        if currentTurn.isEmpty { return committed }
        return committed + " " + currentTurn
    }

    /// - Parameters:
    ///   - transcript: the whole hypothesis for this turn so far.
    ///   - turnIndex: Flux turn number; nil for the v1 shape.
    ///   - endOfTurn: true when Deepgram has settled this turn.
    mutating func apply(transcript: String, turnIndex: Int?, endOfTurn: Bool) {
        let piece = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        // A new turn number means the previous one is done, even if its
        // EndOfTurn was dropped.
        if let turnIndex, let current = currentTurnIndex, turnIndex != current {
            commitCurrentTurn()
        }
        if let turnIndex { currentTurnIndex = turnIndex }

        // An empty transcript is Deepgram reporting silence, not a retraction of
        // what it already showed — keep the tail on screen.
        if !piece.isEmpty { currentTurn = piece }

        if endOfTurn {
            commitCurrentTurn()
            currentTurnIndex = nil
        }
    }

    private mutating func commitCurrentTurn() {
        defer { currentTurn = "" }
        let piece = currentTurn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !piece.isEmpty else { return }
        committed = committed.isEmpty ? piece : committed + " " + piece
    }

    mutating func reset() {
        committed = ""
        currentTurn = ""
        currentTurnIndex = nil
    }
}

/// Streaming speech-to-text over Deepgram's WebSocket API.
///
/// Unlike the OpenAI-compatible `/audio/transcriptions` endpoint — request and
/// response, no partial results by construction — this keeps a socket open and
/// returns hypotheses while the user is still speaking, which is what makes a
/// live transcript possible on a machine that cannot run Whisper in realtime.
final class DeepgramStreamingClient: NSObject, @unchecked Sendable {
    struct Config {
        var apiKey: String
        var model: String
        /// Deepgram language code, or nil to let the model detect it. The
        /// multilingual Flux models detect language themselves.
        var language: String?
        var sampleRate: Int = 16000
        var baseURL: String = DeepgramStreamingClient.defaultBaseURL
        /// How confident Flux must be that the speaker finished before it
        /// settles a turn. Lower reacts sooner and revises more often.
        var endOfTurnThreshold: Double = 0.7
        /// Hard cap on waiting for a turn to end.
        var endOfTurnTimeoutMs: Int = 5000
    }

    static let defaultBaseURL = "wss://api.deepgram.com/v2/listen"
    static let defaultModel = "flux-general-multi"

    /// Called on an arbitrary thread with the full text so far.
    var onTranscript: ((String) -> Void)?
    /// Called once when the stream fails. The caller should stop sending audio.
    var onError: ((String) -> Void)?

    private let config: Config
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private let lock = NSLock()
    private var assembler = DeepgramTranscriptAssembler()
    private var isStopped = false

    init(config: Config) {
        self.config = config
    }

    static func endpoint(for config: Config) -> URL? {
        var components = URLComponents(string: config.baseURL)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "model", value: config.model),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: String(config.sampleRate)),
            // Flux decides where a turn ends on its own; these control how eager
            // it is to call one, which is what sets the perceived latency.
            URLQueryItem(name: "eot_threshold", value: String(config.endOfTurnThreshold)),
            URLQueryItem(name: "eot_timeout_ms", value: String(config.endOfTurnTimeoutMs))
        ]
        if let language = config.language {
            items.append(URLQueryItem(name: "language", value: language))
        }
        components?.queryItems = items
        return components?.url
    }

    func start() throws {
        guard let url = Self.endpoint(for: config) else {
            throw TranscriptionServiceError.invalidURL
        }
        var request = URLRequest(url: url)
        // Deepgram authenticates the handshake with a Token header.
        request.setValue("Token \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task
        task.resume()
        receiveNext()
    }

    /// Feeds one batch of 16 kHz mono Float32 samples.
    func send(samples: [Float]) {
        lock.lock()
        let stopped = isStopped
        let task = self.task
        lock.unlock()
        guard !stopped, let task else { return }

        // Deepgram's linear16 encoding is signed 16-bit little-endian PCM.
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            let value = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: value.littleEndian) { pcm.append(contentsOf: $0) }
        }
        task.send(.data(pcm)) { [weak self] error in
            guard let error else { return }
            self?.fail("send failed: \(error.localizedDescription)")
        }
    }

    /// Closes the stream. Safe to call more than once.
    func stop() {
        lock.lock()
        if isStopped {
            lock.unlock()
            return
        }
        isStopped = true
        let task = self.task
        self.task = nil
        lock.unlock()

        // Ask Deepgram to flush what it has before the socket goes away.
        if let task {
            let close = #"{"type":"CloseStream"}"#
            task.send(.string(close)) { _ in
                task.cancel(with: .normalClosure, reason: nil)
            }
        }
        session?.invalidateAndCancel()
        session = nil
    }

    private func receiveNext() {
        lock.lock()
        let task = self.task
        lock.unlock()
        guard let task else { return }

        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.fail(error.localizedDescription)
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handle(payload: Data(text.utf8))
                case .data(let data):
                    self.handle(payload: data)
                @unknown default:
                    break
                }
                self.receiveNext()
            }
        }
    }

    private func handle(payload: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return }

        // Deepgram reports a refused connection or a bad key as a JSON frame
        // rather than a socket failure, so surface those too.
        let event = object["event"] as? String
        if event == "Error" || object["error"] != nil {
            let message = (object["description"] as? String)
                ?? (object["error"] as? String)
                ?? (object["message"] as? String)
                ?? "Deepgram returned an error"
            fail(message)
            return
        }

        let transcript: String
        let turnIndex: Int?
        let endOfTurn: Bool

        if let fluxTranscript = object["transcript"] as? String {
            // v2 (Flux): turn-based.
            transcript = fluxTranscript
            turnIndex = object["turn_index"] as? Int
            endOfTurn = (event == "EndOfTurn")
        } else if let channel = object["channel"] as? [String: Any],
                  let alternatives = channel["alternatives"] as? [[String: Any]],
                  let v1Transcript = alternatives.first?["transcript"] as? String {
            // v1: interim/final, one segment at a time.
            transcript = v1Transcript
            turnIndex = nil
            endOfTurn = (object["is_final"] as? Bool) ?? false
        } else {
            return
        }

        lock.lock()
        assembler.apply(transcript: transcript, turnIndex: turnIndex, endOfTurn: endOfTurn)
        let text = assembler.text
        lock.unlock()

        guard !text.isEmpty else { return }
        onTranscript?(text)
    }

    private func fail(_ message: String) {
        lock.lock()
        let alreadyStopped = isStopped
        isStopped = true
        lock.unlock()
        guard !alreadyStopped else { return }
        fputs("[Deepgram] \(message)\n", stderr)
        onError?(message)
    }
}
