import ATVRemoteKit
import Foundation

@MainActor
final class RemoteViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case connecting
        case pairingCodeRequired
        case pairing
        case connected
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var pairingCode = ""
    @Published var deviceDescription = ""
    @Published var currentApp = ""

    private let host: String
    private var identity: ClientIdentity?
    private var remote: RemoteSession?
    private var pairing: PairingSession?

    init(host: String) {
        self.host = host
    }

    func connect() async {
        phase = .connecting
        do {
            let identity = try ClientIdentity.loadOrCreate()
            self.identity = identity
            try await connectRemote(identity: identity)
        } catch {
            // Not paired yet (or TV rejected the certificate) — start pairing.
            await startPairing()
        }
    }

    private func connectRemote(identity: ClientIdentity) async throws {
        let remote = RemoteSession(host: host, identity: identity)
        remote.onCurrentAppUpdated = { [weak self] app in
            Task { @MainActor in self?.currentApp = app }
        }
        try await remote.connect()
        self.remote = remote
        if let info = remote.deviceInfo {
            deviceDescription = "\(info.vendor) \(info.model) (sw \(info.version))"
        }
        phase = .connected
    }

    private func startPairing() async {
        guard let identity else {
            phase = .failed("証明書の準備に失敗しました")
            return
        }
        do {
            let pairing = PairingSession(host: host, clientName: "ATVRemote iOS", identity: identity)
            self.pairing = pairing
            try await pairing.start()
            phase = .pairingCodeRequired
        } catch {
            phase = .failed("ペアリング開始に失敗: \(error.localizedDescription)")
        }
    }

    func submitPairingCode() async {
        guard let pairing, let identity else { return }
        phase = .pairing
        do {
            try await pairing.finish(code: pairingCode)
            self.pairing = nil
            try await connectRemote(identity: identity)
        } catch {
            phase = .failed("ペアリング失敗: \(error.localizedDescription)")
        }
    }

    func send(_ key: Remote_RemoteKeyCode) {
        remote?.sendKey(key)
    }

    func launch(_ url: String) {
        remote?.launchApp(url)
    }

    func disconnect() {
        pairing?.cancel()
        remote?.disconnect()
        remote = nil
    }
}
