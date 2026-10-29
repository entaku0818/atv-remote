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
    }

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "atvremotekit.discovery")
    private var devices: [String: Device] = [:]
    private var onUpdate: (@Sendable ([Device]) -> Void)?

    public init() {}

    public func start(onUpdate: @escaping @Sendable ([Device]) -> Void) {
        self.onUpdate = onUpdate
        let browser = NWBrowser(
            for: .bonjour(type: "_androidtvremote2._tcp", domain: nil),
            using: NWParameters()
        )
        self.browser = browser
        browser.stateUpdateHandler = { state in
            switch state {
            case .failed(let error), .waiting(let error):
                ATVLog.error("discovery", "browser \(state): \(error)")
            default:
                ATVLog.debug("discovery", "browser \(state)")
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            self.devices = [:]
            ATVLog.info("discovery", "found \(results.count) service(s)")
            for result in results {
                if case .service(let name, _, _, _) = result.endpoint {
                    self.devices[name] = Device(name: name, host: nil, port: nil, endpoint: result.endpoint)
                    self.resolve(name: name, endpoint: result.endpoint)
                }
            }
            self.notify()
        }
        browser.start(queue: queue)
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Resolves a Bonjour endpoint to an IPv4 host/port by opening a throwaway connection.
    private func resolve(name: String, endpoint: NWEndpoint) {
        let params = NWParameters.tcp
        params.includePeerToPeer = false
        if let ipOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: params)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                if let path = connection.currentPath,
                   case .hostPort(let host, let port) = path.remoteEndpoint {
                    let hostString: String
                    switch host {
                    case .ipv4(let v4): hostString = "\(v4)"
                    case .ipv6(let v6): hostString = "\(v6)"
                    case .name(let n, _): hostString = n
                    @unknown default: hostString = "\(host)"
                    }
                    ATVLog.info("discovery", "resolved \(name) -> \(hostString):\(port)")
                    self.queue.async {
                        self.devices[name] = Device(
                            name: name,
                            host: hostString.components(separatedBy: "%").first,
                            port: port.rawValue,
                            endpoint: endpoint
                        )
                        self.notify()
                    }
                }
                connection.cancel()
            } else if case .failed(let error) = state {
                ATVLog.error("discovery", "resolve \(name) failed: \(error)")
                connection.cancel()
            }
        }
        connection.start(queue: queue)
    }

    private func notify() {
        onUpdate?(devices.values.sorted { $0.name < $1.name })
    }
}
