import Combine
import ATVRemoteKit
import Foundation

/// Outcome of the last button press, shown under the connection status.
struct ResultMessage: Equatable {
    enum Kind { case info, success, warning, failure }
    let kind: Kind
    let text: String
}

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
    @Published var pairingCode = "" {
        didSet {
            let normalized = RemoteInput.pairingCode(pairingCode)
            if normalized != pairingCode { pairingCode = normalized }
        }
    }
    @Published var deviceDescription = ""
    @Published var currentApp = ""
    @Published var result: ResultMessage?

    /// How long to wait for the TV to report a new foreground app after a launch.
    private let launchTimeout: Duration = .seconds(5)
    private var pendingLaunch: (url: String, previousApp: String)?
    private var launchTimeoutTask: Task<Void, Never>?

    private var generation = UUID()
    private let host: String
    private var identity: ClientIdentity?
    private var remote: RemoteSession?
    private var pairing: PairingSession?

    init(host: String) {
        self.host = host
    }

    func connect() async {
        disconnect()
        let attempt = generation
        phase = .connecting
        result = nil
        pairingCode = ""
        currentApp = ""
        deviceDescription = ""
        do {
            let identity = try ClientIdentity.loadOrCreate()
            self.identity = identity
            do {
                try await connectRemote(identity: identity, attempt: attempt)
            } catch is CancellationError {
                if generation == attempt { phase = .idle }
            } catch ATVError.timedOut {
                if generation == attempt { phase = .failed("TVが応答しません。電源と同じネットワークへの接続を確認してください。") }
            } catch {
                guard generation == attempt, !Task.isCancelled else { return }
                await startPairing(attempt: attempt)
            }
        } catch {
            guard generation == attempt else { return }
            phase = .failed("接続情報を読み込めません。iPhoneのロックを解除して、もう一度お試しください。")
        }
    }

    private func connectRemote(identity: ClientIdentity, attempt: UUID) async throws {
        let remote = RemoteSession(host: host, identity: identity)
        remote.onCurrentAppUpdated = { [weak self, weak remote] app in
            Task { @MainActor in
                guard let self, let remote, self.remote === remote else { return }
                self.currentAppDidUpdate(app)
            }
        }
        remote.onClosed = { [weak self, weak remote] error in
            Task { @MainActor in
                guard let self, let remote, self.remote === remote else { return }
                self.remoteDidClose(error)
            }
        }
        self.remote = remote
        do {
            try await remote.connect()
            try Task.checkCancellation()
            guard generation == attempt else { throw CancellationError() }
            guard remote.isConnected else { throw ATVError.connectionClosed("closed during connection") }
        } catch {
            if self.remote === remote { self.remote = nil }
            remote.disconnect()
            throw error
        }
        if let info = remote.deviceInfo {
            deviceDescription = "\(info.vendor) \(info.model) (sw \(info.version))"
        }
        phase = .connected
    }

    private func startPairing(attempt: UUID) async {
        guard let identity else {
            phase = .failed("証明書の準備に失敗しました")
            return
        }
        do {
            let pairing = PairingSession(host: host, clientName: "ATVRemote iOS", identity: identity)
            self.pairing = pairing
            try await pairing.start()
            try Task.checkCancellation()
            guard generation == attempt else { pairing.cancel(); return }
            phase = .pairingCodeRequired
        } catch {
            guard generation == attempt else { return }
            pairing?.cancel()
            pairing = nil
            if error is CancellationError { phase = .idle; return }
            phase = .failed("ペアリング開始に失敗: \(error.localizedDescription)")
        }
    }

    func submitPairingCode() async {
        guard phase == .pairingCodeRequired, pairingCode.count == 6,
              let pairing, let identity else { return }
        let attempt = generation
        phase = .pairing
        do {
            try await pairing.finish(code: pairingCode)
            try Task.checkCancellation()
            guard generation == attempt else { pairing.cancel(); return }
            self.pairing = nil
            try await connectRemote(identity: identity, attempt: attempt)
        } catch {
            pairing.cancel()
            guard generation == attempt else { return }
            self.pairing = nil
            if error is CancellationError { phase = .idle; return }
            phase = .failed("ペアリング失敗: \(error.localizedDescription)")
        }
    }

    func send(_ key: Remote_RemoteKeyCode, label: String) {
        guard let remote, remote.isConnected else {
            result = ResultMessage(kind: .failure, text: "「\(label)」を送れませんでした: TVとの接続が切れています")
            return
        }
        remote.sendKey(key)
        result = ResultMessage(kind: .info, text: "「\(label)」を送信しました")
    }

    func launch(_ rawURL: String) {
        let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        log("launch tapped")
        if let problem = RemoteInput.linkError(url) {
            result = ResultMessage(kind: .failure, text: problem)
            log("launch rejected: \(problem)")
            return
        }
        guard let remote, remote.isConnected else {
            result = ResultMessage(kind: .failure, text: "送れませんでした: TVとの接続が切れています。再接続してください")
            return
        }
        if !remote.supportsAppLink {
            result = ResultMessage(kind: .failure, text: "このTVはURLでのアプリ起動に対応していません（APP_LINK未対応）")
            return
        }
        remote.launchApp(url)
        LinkHistory.shared.add(url)
        pendingLaunch = (url, currentApp)
        result = ResultMessage(kind: .info, text: "送信しました。TVの反応を待っています…")
        launchTimeoutTask?.cancel()
        launchTimeoutTask = Task { [weak self, launchTimeout] in
            try? await Task.sleep(for: launchTimeout)
            guard !Task.isCancelled else { return }
            self?.launchTimedOut()
        }
    }

    private func currentAppDidUpdate(_ app: String) {
        currentApp = app
        guard let pending = pendingLaunch else { return }
        pendingLaunch = nil
        launchTimeoutTask?.cancel()
        if app == pending.previousApp {
            result = ResultMessage(kind: .success, text: "TVが応答しました（\(app)）")
        } else {
            result = ResultMessage(kind: .success, text: "TVで \(app) が開きました")
        }
    }

    private func launchTimedOut() {
        guard pendingLaunch != nil else { return }
        pendingLaunch = nil
        let seconds = launchTimeout.components.seconds
        let text = "\(seconds)秒待ってもTVのアプリが切り替わりませんでした。"
            + "URLが正しいか、TVにそのアプリが入っているか確認してください"
        result = ResultMessage(kind: .warning, text: text)
        log("no app change within \(seconds)s after launch")
    }

    private func remoteDidClose(_ error: Error?) {
        launchTimeoutTask?.cancel()
        pendingLaunch = nil
        let previous = remote
        remote = nil
        previous?.disconnect()
        let reason = error?.localizedDescription ?? "TVが接続を閉じました"
        phase = .failed("接続が切れました: \(reason)")
        result = nil
    }

    private func log(_ message: String) {
        ATVLog.info("app", message)
    }

    /// Called when the app returns to the foreground. iOS drops sockets in the
    /// background, so reconnect if the session was lost while away.
    func reconnectIfNeeded() async {
        guard phase == .idle || { if case .failed = phase { return true }; return false }() else { return }
        log("app became active; reconnecting")
        await connect()
    }

    func disconnect() {
        generation = UUID()
        phase = .idle
        launchTimeoutTask?.cancel()
        pendingLaunch = nil
        pairing?.cancel()
        pairing = nil
        let remote = remote
        self.remote = nil
        remote?.disconnect()
    }
}
