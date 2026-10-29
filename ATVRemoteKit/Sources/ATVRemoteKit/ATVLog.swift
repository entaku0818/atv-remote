import Foundation
import os

/// Logging for ATVRemoteKit. Every message goes to the unified log
/// (subsystem "ATVRemoteKit", visible in Xcode / Console.app) and, when set,
/// to `ATVLog.handler` so an app can show it on screen.
public enum ATVLog {
    public enum Level: String, Sendable {
        case debug
        case info
        case error
    }

    public struct Entry: Sendable {
        public let date: Date
        public let level: Level
        public let category: String
        public let message: String
    }

    private static let lock = NSLock()
    private static var _handler: (@Sendable (Entry) -> Void)?

    /// Called for every log entry, on an arbitrary queue.
    public static var handler: (@Sendable (Entry) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); defer { lock.unlock() }; _handler = newValue }
    }

    public static func debug(_ category: String, _ message: String) {
        log(.debug, category, message)
    }

    public static func info(_ category: String, _ message: String) {
        log(.info, category, message)
    }

    public static func error(_ category: String, _ message: String) {
        log(.error, category, message)
    }

    public static func log(_ level: Level, _ category: String, _ message: String) {
        let logger = Logger(subsystem: "ATVRemoteKit", category: category)
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        handler?(Entry(date: Date(), level: level, category: category, message: message))
    }
}
