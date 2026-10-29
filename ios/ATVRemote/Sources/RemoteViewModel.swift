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
    @Published var pairingCode = ""
    @Published var deviceDescription = ""
    @Published var currentApp = ""
    @Published var result: ResultMessage?

    /// How long to wait for the TV to report a new foreground app after a launch.
    private let launchTimeout: Duration = .seconds(5)
    private var pendingLaunch: (url: String, previousApp: String)?
    private var launchTimeoutTask: Task<Void, Never>?

    private let host: String
    private var identity: ClientIdentity?
    private var remote: RemoteSession?
    private var pairing: PairingSession?

    init(host: String) {
        self.host = host
    }

    func connect() async {
        phase = .connecting
        result = nil
        log("connect to \(host)")
        do {
            let identity = try ClientIdentity.loadOrCreate()
            self.identity = identity
            try await connectRemote(identity: identity)
        } catch {
            // Not paired yet (or TV rejected the certificate) — start pairing.
            log("remote connect failed (\(error.localizedDescription)); start pairing")
            await startPairing()
        }
    }

    private func connectRemote(identity: ClientIdentity) async throws {
        let remote = RemoteSession(host: host, identity: identity)
        remote.onCurrentAppUpdated = { [weak self] app in
            Task { @MainActor in self?.currentAppDidUpdate(app) }
        }
        remote.onClosed = { [weak self, weak remote] error in
            Task { @MainActor in
                guard let self, let remote, self.remote === remote else { return }
                self.remoteDidClose(error)
            }
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
        log("launch tapped: \(url)")
        if let problem = Self.validate(url) {
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
        pendingLaunch = (url, currentApp)
        result = ResultMessage(kind: .info, text: "送信しました。TVの反応を待っています…")
        launchTimeoutTask?.cancel()
        launchTimeoutTask = Task { [weak self, launchTimeout] in
            try? await Task.sleep(for: launchTimeout)
            guard !Task.isCancelled else { return }
            self?.launchTimedOut()
        }
    }

    /// Returns a user-facing reason when the URL obviously cannot open anything.
    private static func validate(_ url: String) -> String? {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme, ["http", "https"].contains(scheme.lowercased()),
              let host = components.host, !host.isEmpty else {
            return "URLの形式が正しくありません"
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if host.hasSuffix("tver.jp"), path == "episodes" || path == "series" || path.isEmpty {
            return "TVerのURLにエピソード（またはシリーズ）のIDがありません。TVerアプリの共有からURLをコピーしてください"
        }
        return nil
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
        guard let pending = pendingLaunch else { return }
        pendingLaunch = nil
        let seconds = launchTimeout.components.seconds
        let text = "\(seconds)秒待ってもTVのアプリが切り替わりませんでした。"
            + "URLが正しいか、TVにそのアプリが入っているか確認してください"
        result = ResultMessage(kind: .warning, text: text)
        log("no app change within \(seconds)s after launching \(pending.url)")
    }

    private func remoteDidClose(_ error: Error?) {
        launchTimeoutTask?.cancel()
        pendingLaunch = nil
        remote = nil
        let reason = error?.localizedDescription ?? "TVが接続を閉じました"
        phase = .failed("接続が切れました: \(reason)")
        result = nil
    }

    private func log(_ message: String) {
        ATVLog.info("app", message)
    }

    func disconnect() {
        launchTimeoutTask?.cancel()
        pendingLaunch = nil
        pairing?.cancel()
        let remote = remote
        self.remote = nil
        remote?.disconnect()
    }
}
