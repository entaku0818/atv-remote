import ATVRemoteKit
import Foundation

/// Keeps recent ATVRemoteKit / app log lines so they can be shown in the app.
@MainActor
final class LogStore: ObservableObject {
    static let shared = LogStore()

    struct Line: Identifiable {
        let id = UUID()
        let entry: ATVLog.Entry

        var text: String {
            "\(Self.formatter.string(from: entry.date)) [\(entry.category)] \(entry.message)"
        }

        private static let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter
        }()
    }

    @Published private(set) var lines: [Line] = []
    private let maxLines = 300

    /// Routes ATVRemoteKit logs into this store. Call once at launch.
    func install() {
        ATVLog.handler = { entry in
            Task { @MainActor in LogStore.shared.append(entry) }
        }
    }

    func clear() {
        lines.removeAll()
    }

    var allText: String {
        lines.map(\.text).joined(separator: "\n")
    }

    private func append(_ entry: ATVLog.Entry) {
        // Pings arrive every few seconds; keep them in the system log only.
        if entry.level == .debug { return }
        lines.append(Line(entry: entry))
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }
}
