import Foundation
import Combine

/// A single saved dictation result.
struct HistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    let date: Date
    let languageCode: String
    let modelName: String
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        text: String,
        date: Date = Date(),
        languageCode: String,
        modelName: String,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.text = text
        self.date = date
        self.languageCode = languageCode
        self.modelName = modelName
        self.isFavorite = isFavorite
    }
}

/// Local, on-disk dictation history. No cloud sync — everything stays in
/// `~/Library/Application Support/Lyra/history.json`.
final class HistoryStore: ObservableObject, @unchecked Sendable {
    static let shared = HistoryStore()

    @Published private(set) var items: [HistoryItem] = []
    @Published var searchQuery: String = "" {
        didSet { updateFilteredItems() }
    }
    @Published private(set) var filteredItems: [HistoryItem] = []

    private let fileManager = FileManager.default
    private let maxItems = 1000
    private var saveCancellable: AnyCancellable?

    private var historyFileURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Lyra", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    private init() {
        load()

        // Debounce auto-save so rapid mutations (batch delete) coalesce.
        saveCancellable = $items
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.global(qos: .utility))
            .sink { [weak self] _ in
                self?.save()
            }
    }

    // MARK: - Persistence

    private func load() {
        let url = historyFileURL
        guard fileManager.fileExists(atPath: url.path) else {
            items = []
            filteredItems = []
            return
        }

        do {
            let data = try Data(contentsOf: url)
            items = try JSONDecoder().decode([HistoryItem].self, from: data)
            updateFilteredItems()
        } catch {
            fputs("[HistoryStore] Failed to load history: \(error)\n", stderr)
            items = []
            filteredItems = []
        }
    }

    private func save() {
        let url = historyFileURL
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: url, options: .atomic)
        } catch {
            fputs("[HistoryStore] Failed to save history: \(error)\n", stderr)
        }
    }

    private func updateFilteredItems() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter { item in
                item.text.lowercased().contains(query)
            }
        }
    }

    // MARK: - Mutations

    /// Add a new transcription to the top of history. Trims history to `maxItems`.
    func add(text: String, language: Language, modelName: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let item = HistoryItem(
            text: text,
            languageCode: language.rawValue,
            modelName: modelName
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.items.insert(item, at: 0)
            if self.items.count > self.maxItems {
                self.items.removeLast(self.items.count - self.maxItems)
            }
            self.updateFilteredItems()
        }
    }

    func delete(item: HistoryItem) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.items.removeAll { $0.id == item.id }
            self.updateFilteredItems()
        }
    }

    func toggleFavorite(item: HistoryItem) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let index = self.items.firstIndex(where: { $0.id == item.id })
            else { return }
            self.items[index].isFavorite.toggle()
            self.updateFilteredItems()
        }
    }

    func clearAll() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.items.removeAll()
            self.updateFilteredItems()
        }
    }

    /// Replace the entire text of an item (e.g. after a quick inline edit).
    func updateText(for item: HistoryItem, to text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let index = self.items.firstIndex(where: { $0.id == item.id })
            else { return }
            self.items[index].text = text
            self.updateFilteredItems()
        }
    }
}
