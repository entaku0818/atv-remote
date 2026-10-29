import Foundation

/// URLs sent with "TVで開く", newest first, persisted in UserDefaults.
@MainActor
final class LinkHistory: ObservableObject {
    static let shared = LinkHistory()

    struct Item: Codable, Identifiable, Equatable {
        var id: String { url }
        let url: String
        let sentAt: Date
    }

    @Published private(set) var items: [Item] = []

    private let defaults: UserDefaults
    private let key = "linkHistory"
    private let maxItems = 30

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved
        }
    }

    func add(_ url: String) {
        items.removeAll { $0.url == url }
        items.insert(Item(url: url, sentAt: Date()), at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        save()
    }

    func remove(_ item: Item) {
        items.removeAll { $0 == item }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
