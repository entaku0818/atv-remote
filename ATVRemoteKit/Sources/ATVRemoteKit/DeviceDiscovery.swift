import Foundation
import Network

/// Discovers Android TVs advertising _androidtvremote2._tcp via Bonjour.
public final class DeviceDiscovery: @unchecked Sendable {
    public struct Device: Identifiable, Hashable, Sendable {
        public var id: String { name }
        public let name: String
        public let host: String?
        public let port: UInt16?
        public let endpoint: NWEndpoint

        public static func manual(host: String) -> Device {
            Device(name: host, host: host, port: 6466, endpoint: .hostPort(host: .init(host), port: 6466))
        }
    }

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "atvremotekit.discovery")
    private var devices: [String: Device] = [:]
    private var resolvers: [String: NWConnection] = [:]
    private var onUpdate: (@Sendable ([Device]) -> Void)?
    private var generation = UUID()

    public init() {}

    public func start(
        onError: (@Sendable (String) -> Void)? = nil,
        onUpdate: @escaping @Sendable ([Device]) -> Void
    ) {
        queue.async { [self] in
            stopOnQueue()
            self.onUpdate = onUpdate
            let generation = self.generation
            let browser = NWBrowser(for: .bonjour(type: "_androidtvremote2._tcp", domain: nil), using: NWParameters())
            self.browser = browser
            browser.stateUpdateHandler = { [weak self] state in
                guard self?.generation == generation else { return }
                if case .failed = state { onError?("TVを検索できません。ネットワークとローカルネットワークの許可を確認してください。") }
                if case .waiting = state { onError?("ネットワーク接続を待っています。Wi-Fiと設定アプリのアクセス許可を確認してください。") }
            }
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self, self.generation == generation else { return }
                self.resolvers.values.forEach { $0.stateUpdateHandler = nil; $0.cancel() }
                self.resolvers.removeAll()
                self.devices.removeAll()
                for result in results {
                    if case .service(let name, _, _, _) = result.endpoint {
                        self.devices[name] = Device(name: name, host: nil, port: nil, endpoint: result.endpoint)
                        self.resolve(name: name, endpoint: result.endpoint, generation: generation)
                    }
                }
                self.notify()
            }
            browser.start(queue: queue)
        }
    }

    public func stop() {
        queue.async { [self] in stopOnQueue() }
    }

    private func stopOnQueue() {
        generation = UUID()
        browser?.stateUpdateHandler = nil
        browser?.browseResultsChangedHandler = nil
        browser?.cancel()
        browser = nil
        resolvers.values.forEach { $0.stateUpdateHandler = nil; $0.cancel() }
        resolvers.removeAll()
        devices.removeAll()
        onUpdate = nil
    }

    private func resolve(name: String, endpoint: NWEndpoint, generation: UUID) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        resolvers[name] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.generation == generation,
                  self.resolvers[name] === connection else { return }
            switch state {
            case .ready:
                if let path = connection.currentPath, case .hostPort(let host, let port) = path.remoteEndpoint {
                    self.devices[name] = Device(name: name, host: "\(host)", port: port.rawValue, endpoint: endpoint)
                    self.notify()
                }
                self.finishResolving(name, connection: connection)
            case .failed, .cancelled:
                self.finishResolving(name, connection: connection)
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 10) { [weak self, weak connection] in
            guard let self, let connection, self.resolvers[name] === connection else { return }
            self.finishResolving(name, connection: connection)
        }
    }

    private func finishResolving(_ name: String, connection: NWConnection) {
        connection.stateUpdateHandler = nil
        connection.cancel()
        resolvers.removeValue(forKey: name)
    }

    private func notify() {
        onUpdate?(devices.values.sorted { $0.name < $1.name })
    }
}
