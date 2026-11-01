import Foundation
import Network
import Security

/// TLS connection to an Android TV that sends/receives varint-framed protobuf
/// messages. Presents the client identity and accepts the TV's self-signed
/// server certificate (capturing it for the pairing secret).
final class ProtobufConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let label: String
    private let queue = DispatchQueue(label: "atvremotekit.connection")
    private var framer = MessageFramer()

    /// Lock-protected box so the TLS verify block can run before init completes.
    private final class CertificateBox: @unchecked Sendable {
        private let lock = NSLock()
        private var certificate: SecCertificate?
        var value: SecCertificate? {
            get { lock.lock(); defer { lock.unlock() }; return certificate }
            set { lock.lock(); defer { lock.unlock() }; certificate = newValue }
        }
    }

    private let serverCertificateBox = CertificateBox()

    /// The TV's leaf certificate, available once the TLS handshake completed.
    var serverCertificate: SecCertificate? { serverCertificateBox.value }

    var onMessage: ((Data) -> Void)?
    var onClosed: ((Error?) -> Void)?

    init(host: String, port: UInt16, identity: ClientIdentity, acceptUnpairedServer: Bool = false) {
        label = "\(host):\(port)"
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        if let secIdentity = sec_identity_create(identity.identity) {
            sec_protocol_options_set_local_identity(options, secIdentity)
        }
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        let box = serverCertificateBox
        sec_protocol_options_set_verify_block(options, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            if let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
               let leaf = chain.first {
                box.value = leaf
            }
            guard let certificate = box.value else { complete(false); return }
            if acceptUnpairedServer {
                // The pairing secret validates this certificate against the code shown on the TV.
                complete(true)
            } else {
                let matches = try? ServerCertificateStore.matches(SecCertificateCopyData(certificate) as Data, host: host)
                complete(matches == true)
            }
        }, queue)

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: tls, tcp: tcp)
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: params
        )
    }

    func start() async throws {
        let ready = AsyncSignal()
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                ready.resolve(.success(()))
            case .failed(let error), .waiting(let error):
                ready.resolve(.failure(error))
                self?.onClosed?(error)
                self?.connection.cancel()
            case .cancelled:
                ready.resolve(.failure(CancellationError()))
                self?.onClosed?(nil)
            default: break
            }
        }
        connection.start(queue: queue)
        do {
            try await ready.wait()
            receiveLoop()
        } catch {
            connection.cancel()
            throw error
        }
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                do {
                    for message in try self.framer.append(data) { self.onMessage?(message) }
                } catch {
                    self.onClosed?(error)
                    self.connection.cancel()
                    return
                }
            }
            if let error {
                ATVLog.error("connection", "\(self.label) receive error: \(error)")
                self.onClosed?(error)
                return
            }
            if isComplete {
                ATVLog.info("connection", "\(self.label) closed by TV (EOF)")
                self.onClosed?(ATVError.connectionClosed("EOF"))
                return
            }
            self.receiveLoop()
        }
    }

    func send(_ message: Data) {
        let label = label
        connection.send(content: MessageFramer.frame(message), completion: .contentProcessed { error in
            if let error {
                ATVLog.error("connection", "\(label) send failed: \(error)")
            }
        })
    }

    func cancel() {
        connection.cancel()
    }
}
