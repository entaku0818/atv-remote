import Foundation
import Security

/// Pairing protocol with an Android TV (port 6467).
///
/// Flow: PairingRequest → (ack) → Options → (options) → Configuration →
/// (configuration_ack: TV shows a 6-digit code) → Secret → (secret_ack).
public final class PairingSession: @unchecked Sendable {
    private let host: String
    private let clientName: String
    private let identity: ClientIdentity
    private let connection: ProtobufConnection
    private let codeDisplayed = AsyncSignal()
    private let finished = AsyncSignal()

    public init(host: String, port: UInt16 = 6467, clientName: String, identity: ClientIdentity) {
        self.host = host
        self.clientName = clientName
        self.identity = identity
        self.connection = ProtobufConnection(host: host, port: port, identity: identity)
    }

    /// Connects and drives pairing until the TV displays the 6-digit code.
    public func start() async throws {
        connection.onMessage = { [weak self] data in self?.handle(data) }
        connection.onClosed = { [weak self] error in
            self?.fail(ATVError.connectionClosed(error?.localizedDescription ?? "closed"))
        }
        do {
            try await connection.start()
            var msg = newMessage()
            msg.pairingRequest.clientName = clientName
            msg.pairingRequest.serviceName = "atvremote"
            send(msg)
            try await codeDisplayed.wait()
        } catch {
            connection.cancel()
            throw error
        }
    }

    /// Sends the secret computed from the code the user read off the TV screen.
    public func finish(code: String) async throws {
        guard let serverCert = connection.serverCertificate,
              let serverKey = SecCertificateCopyKey(serverCert) else {
            throw ATVError.pairingFailed("no server certificate captured")
        }
        let (serverModulus, serverExponent) = try ClientIdentity.modulusExponent(of: serverKey)
        let (clientModulus, clientExponent) = try identity.publicKeyModulusExponent()
        let secret = try PairingSecret.compute(
            clientModulus: clientModulus, clientExponent: clientExponent,
            serverModulus: serverModulus, serverExponent: serverExponent,
            pairingCode: code
        )
        defer { connection.cancel() }
        var msg = newMessage()
        msg.secret.secret = secret
        send(msg)
        try await finished.wait()
    }

    public func cancel() {
        codeDisplayed.resolve(.failure(CancellationError()))
        finished.resolve(.failure(CancellationError()))
        ATVLog.info("pairing", "cancel requested")
        connection.cancel()
    }

    // MARK: Internals

    private func newMessage() -> Polo_Wire_Protobuf_OuterMessage {
        var msg = Polo_Wire_Protobuf_OuterMessage()
        msg.protocolVersion = 2
        msg.status = .ok
        return msg
    }

    private func send(_ msg: Polo_Wire_Protobuf_OuterMessage) {
        guard let data = try? msg.serializedData() else { return }
        connection.send(data)
    }

    private func handle(_ raw: Data) {
        guard let msg = try? Polo_Wire_Protobuf_OuterMessage(serializedBytes: raw) else {
            fail(ATVError.pairingFailed("cannot parse OuterMessage"))
            return
        }
        guard msg.status == .ok else {
            fail(ATVError.pairingFailed("TV returned status \(msg.status)"))
            return
        }
        if msg.hasPairingRequestAck {
            ATVLog.info("pairing", "pairing_request_ack; send options")
            var reply = newMessage()
            reply.options.preferredRole = .input
            var encoding = Polo_Wire_Protobuf_Options.Encoding()
            encoding.type = .hexadecimal
            encoding.symbolLength = 6
            reply.options.inputEncodings = [encoding]
            send(reply)
        } else if msg.hasOptions {
            ATVLog.info("pairing", "options; send configuration")
            var reply = newMessage()
            reply.configuration.clientRole = .input
            reply.configuration.encoding.type = .hexadecimal
            reply.configuration.encoding.symbolLength = 6
            send(reply)
        } else if msg.hasConfigurationAck {
            ATVLog.info("pairing", "configuration_ack; code should be on the TV screen")
            resumeCodeDisplayed(nil)
        } else if msg.hasSecretAck {
            ATVLog.info("pairing", "secret_ack; paired")
            resumeFinished(nil)
        } else {
            fail(ATVError.pairingFailed("unhandled message"))
        }
    }

    private func resumeCodeDisplayed(_ error: Error?) {
        codeDisplayed.resolve(error.map { .failure($0) } ?? .success(()))
    }

    private func resumeFinished(_ error: Error?) {
        finished.resolve(error.map { .failure($0) } ?? .success(()))
    }

    private func fail(_ error: Error) {
        ATVLog.error("pairing", "failed: \(error.localizedDescription)")
        resumeCodeDisplayed(error)
        resumeFinished(error)
    }
}
