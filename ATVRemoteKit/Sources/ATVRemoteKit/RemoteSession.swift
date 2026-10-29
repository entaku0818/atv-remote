import Foundation

/// Remote-control protocol with a paired Android TV (port 6466).
public final class RemoteSession: @unchecked Sendable {
    public struct DeviceInfo: Sendable {
        public let vendor: String
        public let model: String
        public let version: String
    }

    /// PING | KEY | IME | POWER | VOLUME | APP_LINK (see Feature in androidtvremote2).
    private static let requestedFeatures: UInt32 = 1 | 2 | 4 | 32 | 64 | 512
    private static let appLinkFeature: UInt32 = 512
    private static let featureNames: [(UInt32, String)] = [
        (1, "PING"), (2, "KEY"), (4, "IME"), (8, "VOICE"), (16, "UNKNOWN_16"),
        (32, "POWER"), (64, "VOLUME"), (512, "APP_LINK")
    ]
    private var activeFeatures: UInt32 = requestedFeatures

    private let connection: ProtobufConnection
    private let queue = DispatchQueue(label: "atvremotekit.remote")
    private var startedContinuation: CheckedContinuation<Void, Error>?
    private var isClosed = false

    public private(set) var deviceInfo: DeviceInfo?
    public private(set) var isOn = false
    public private(set) var currentApp = ""
    /// True between remote_start and the connection closing.
    public private(set) var isConnected = false

    /// Whether the TV accepted the APP_LINK feature (needed by `launchApp`).
    public var supportsAppLink: Bool { activeFeatures & Self.appLinkFeature != 0 }

    public var onCurrentAppUpdated: (@Sendable (String) -> Void)?
    public var onIsOnUpdated: (@Sendable (Bool) -> Void)?
    public var onClosed: (@Sendable (Error?) -> Void)?

    public init(host: String, port: UInt16 = 6466, identity: ClientIdentity) {
        self.connection = ProtobufConnection(host: host, port: port, identity: identity)
    }

    /// Connects and completes the RemoteConfigure/RemoteSetActive handshake.
    /// Resolves once the TV sends remote_start. Throws if the TV rejects the
    /// connection (typically: not paired).
    public func connect() async throws {
        connection.onMessage = { [weak self] data in self?.handle(data) }
        connection.onClosed = { [weak self] error in
            guard let self else { return }
            if self.isConnected {
                ATVLog.error("remote", "disconnected: \(error.map { "\($0)" } ?? "closed")")
            }
            self.isConnected = false
            self.isClosed = true
            self.resumeStarted(ATVError.connectionClosed(error?.localizedDescription ?? "closed"))
            self.onClosed?(error)
        }
        try await connection.start()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.sync { self.startedContinuation = cont }
            // The TV speaks first (remote_configure); nothing to send here.
        }
    }

    public func disconnect() {
        ATVLog.info("remote", "disconnect requested")
        connection.cancel()
    }

    public func sendKey(_ keyCode: Remote_RemoteKeyCode, direction: Remote_RemoteDirection = .short) {
        var msg = Remote_RemoteMessage()
        msg.remoteKeyInject.keyCode = keyCode
        msg.remoteKeyInject.direction = direction
        ATVLog.info("remote", "send key \(keyCode) (\(direction))")
        send(msg)
    }

    /// Accepts "DPAD_UP" or "KEYCODE_DPAD_UP" style names.
    public func sendKey(named name: String) throws {
        let full = name.uppercased().hasPrefix("KEYCODE_") ? name.uppercased() : "KEYCODE_" + name.uppercased()
        guard let keyCode = Remote_RemoteKeyCode.allCases.first(where: { "\($0)".uppercased() == camelToScreaming(full) || screamingName(of: $0) == full }) else {
            throw ATVError.pairingFailed("unknown key code: \(name)")
        }
        sendKey(keyCode)
    }

    public func launchApp(_ appLink: String) {
        if !supportsAppLink {
            ATVLog.error("remote", "TV did not accept APP_LINK; launch request may be ignored")
        }
        ATVLog.info("remote", "send app link \(appLink)")
        var msg = Remote_RemoteMessage()
        msg.remoteAppLinkLaunchRequest.appLink = appLink
        send(msg)
    }

    // MARK: Internals

    private func send(_ msg: Remote_RemoteMessage) {
        guard let data = try? msg.serializedData() else {
            ATVLog.error("remote", "failed to serialize message")
            return
        }
        if isClosed {
            ATVLog.error("remote", "sending after the connection closed; the TV will not receive it")
        }
        connection.send(data)
    }

    private func handle(_ raw: Data) {
        guard let msg = try? Remote_RemoteMessage(serializedBytes: raw) else {
            ATVLog.error("remote", "cannot parse RemoteMessage (\(raw.count) bytes)")
            return
        }

        if msg.hasRemoteConfigure {
            let cfg = msg.remoteConfigure
            deviceInfo = DeviceInfo(
                vendor: cfg.deviceInfo.vendor,
                model: cfg.deviceInfo.model,
                version: cfg.deviceInfo.appVersion
            )
            activeFeatures = Self.requestedFeatures & UInt32(cfg.code1)
            ATVLog.info(
                "remote",
                "TV \(cfg.deviceInfo.vendor) \(cfg.deviceInfo.model) supports \(Self.describe(UInt32(cfg.code1))); "
                    + "using \(Self.describe(activeFeatures))"
            )
            var reply = Remote_RemoteMessage()
            reply.remoteConfigure.code1 = Int32(activeFeatures)
            reply.remoteConfigure.deviceInfo.unknown1 = 1
            reply.remoteConfigure.deviceInfo.unknown2 = "1"
            reply.remoteConfigure.deviceInfo.packageName = "atvremote"
            reply.remoteConfigure.deviceInfo.appVersion = "1.0.0"
            send(reply)
        } else if msg.hasRemoteSetActive {
            ATVLog.debug("remote", "set_active")
            var reply = Remote_RemoteMessage()
            reply.remoteSetActive.active = Int32(activeFeatures)
            send(reply)
        } else if msg.hasRemoteStart {
            isOn = msg.remoteStart.started
            isConnected = true
            ATVLog.info("remote", "remote_start (TV is \(isOn ? "on" : "off"))")
            onIsOnUpdated?(isOn)
            resumeStarted(nil)
        } else if msg.hasRemotePingRequest {
            var reply = Remote_RemoteMessage()
            reply.remotePingResponse.val1 = msg.remotePingRequest.val1
            ATVLog.debug("remote", "ping \(msg.remotePingRequest.val1)")
            send(reply)
        } else if msg.hasRemoteImeKeyInject {
            currentApp = msg.remoteImeKeyInject.appInfo.appPackage
            ATVLog.info("remote", "current app: \(currentApp)")
            onCurrentAppUpdated?(currentApp)
        } else if msg.hasRemoteError {
            ATVLog.error("remote", "TV returned remote_error for: \(msg.remoteError.message.textFormatString())")
        } else {
            ATVLog.debug("remote", "unhandled message: \(msg.textFormatString())")
        }
    }

    private static func describe(_ features: UInt32) -> String {
        let names = featureNames.filter { features & $0.0 != 0 }.map(\.1)
        return "\(features) [\(names.joined(separator: ","))]"
    }

    private func resumeStarted(_ error: Error?) {
        queue.sync {
            if let cont = startedContinuation {
                startedContinuation = nil
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    // "KEYCODE_DPAD_UP" ↔ enum case name helpers
    private func screamingName(of keyCode: Remote_RemoteKeyCode) -> String {
        camelToScreaming("\(keyCode)")
    }

    private func camelToScreaming(_ s: String) -> String {
        guard !s.contains("_") else { return s.uppercased() }
        var out = ""
        for ch in s {
            if ch.isUppercase || ch.isNumber, !out.isEmpty { out.append("_") }
            out.append(ch)
        }
        return out.uppercased()
    }
}
