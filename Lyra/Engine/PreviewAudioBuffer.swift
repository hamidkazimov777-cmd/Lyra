import Foundation

/// Thread-safe copy of the audio captured so far, used only by the live preview.
///
/// The preview cannot read `AudioCapture`'s buffer (that one is consumed by the
/// real transcription at stop time), so it keeps its own. Written from the audio
/// tap thread and read from the preview task, hence the lock.
final class PreviewAudioBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    init() {
        // ~30 s at 16 kHz, enough for a typical dictation without reallocating.
        samples.reserveCapacity(16000 * 30)
    }

    func append(_ new: [Float]) {
        lock.lock()
        samples.append(contentsOf: new)
        lock.unlock()
    }

    /// The most recent `maxSamples` samples. Older audio is dropped rather than
    /// growing the work of each preview pass without bound.
    func snapshot(maxSamples: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        guard samples.count > maxSamples else { return samples }
        return Array(samples.suffix(maxSamples))
    }
}
