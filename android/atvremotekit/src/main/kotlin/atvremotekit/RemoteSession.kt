package atvremotekit

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import remote.Remotemessage.RemoteDirection
import remote.Remotemessage.RemoteKeyCode
import remote.Remotemessage.RemoteMessage

/**
 * Remote-control protocol with a paired Android TV (port 6466). Ported from
 * RemoteSession.swift.
 *
 * Unlike swift-protobuf (which renames enum cases to `keycodeDpadUp`-style
 * Swift identifiers), protobuf-java keeps the proto enum constant names
 * verbatim (`KEYCODE_DPAD_UP`), so [sendKey] needs no case-conversion.
 */
class RemoteSession(host: String, port: Int = 6466, private val identity: ClientIdentity) {
    data class DeviceInfo(val vendor: String, val model: String, val version: String)

    companion object {
        // PING | KEY | IME | POWER | VOLUME | APP_LINK (see Feature in androidtvremote2).
        private const val REQUESTED_FEATURES = 1 or 2 or 4 or 32 or 64 or 512
    }

    private var activeFeatures = REQUESTED_FEATURES
    private val connection = ProtobufConnection(host, port, identity)
    private var startedDeferred: CompletableDeferred<Unit>? = null

    var deviceInfo: DeviceInfo? = null
        private set
    var isOn: Boolean = false
        private set
    var currentApp: String = ""
        private set

    var onCurrentAppUpdated: ((String) -> Unit)? = null
    var onIsOnUpdated: ((Boolean) -> Unit)? = null
    var onClosed: ((Throwable?) -> Unit)? = null

    /**
     * Connects and completes the RemoteConfigure/RemoteSetActive handshake.
     * Resolves once the TV sends remote_start. Throws if the TV rejects the
     * connection (typically: not paired).
     */
    suspend fun connect() {
        connection.onMessage = { handle(it) }
        connection.onClosed = { error ->
            resumeStarted(ATVError.ConnectionClosed(error?.message ?: "closed"))
            onClosed?.invoke(error)
        }
        withContext(Dispatchers.IO) { connection.connect() }
        val deferred = CompletableDeferred<Unit>()
        startedDeferred = deferred
        // The TV speaks first (remote_configure); nothing to send here.
        deferred.await()
    }

    fun disconnect() = connection.cancel()

    fun sendKey(keyCode: RemoteKeyCode, direction: RemoteDirection = RemoteDirection.SHORT) {
        send(
            RemoteMessage.newBuilder().apply {
                remoteKeyInjectBuilder.keyCode = keyCode
                remoteKeyInjectBuilder.direction = direction
            }.build(),
        )
    }

    /** Accepts "DPAD_UP" or "KEYCODE_DPAD_UP" style names. */
    fun sendKey(name: String) {
        val full = if (name.uppercase().startsWith("KEYCODE_")) name.uppercase() else "KEYCODE_" + name.uppercase()
        val keyCode = try {
            RemoteKeyCode.valueOf(full)
        } catch (e: IllegalArgumentException) {
            throw ATVError.PairingFailed("unknown key code: $name")
        }
        sendKey(keyCode)
    }

    fun launchApp(appLink: String) {
        send(RemoteMessage.newBuilder().apply { remoteAppLinkLaunchRequestBuilder.appLink = appLink }.build())
    }

    // MARK: Internals

    private fun send(msg: RemoteMessage) = connection.send(msg)

    private fun handle(raw: ByteArray) {
        val msg = try {
            RemoteMessage.parseFrom(raw)
        } catch (e: Exception) {
            return
        }

        when {
            msg.hasRemoteConfigure() -> {
                val cfg = msg.remoteConfigure
                deviceInfo = DeviceInfo(
                    vendor = cfg.deviceInfo.vendor,
                    model = cfg.deviceInfo.model,
                    version = cfg.deviceInfo.appVersion,
                )
                activeFeatures = REQUESTED_FEATURES and cfg.code1
                send(
                    RemoteMessage.newBuilder().apply {
                        remoteConfigureBuilder.code1 = activeFeatures
                        remoteConfigureBuilder.deviceInfoBuilder.unknown1 = 1
                        remoteConfigureBuilder.deviceInfoBuilder.unknown2 = "1"
                        remoteConfigureBuilder.deviceInfoBuilder.packageName = "atvremote"
                        remoteConfigureBuilder.deviceInfoBuilder.appVersion = "1.0.0"
                    }.build(),
                )
            }
            msg.hasRemoteSetActive() -> send(
                RemoteMessage.newBuilder().apply { remoteSetActiveBuilder.active = activeFeatures }.build(),
            )
            msg.hasRemoteStart() -> {
                isOn = msg.remoteStart.started
                onIsOnUpdated?.invoke(isOn)
                resumeStarted(null)
            }
            msg.hasRemotePingRequest() -> send(
                RemoteMessage.newBuilder().apply {
                    remotePingResponseBuilder.val1 = msg.remotePingRequest.val1
                }.build(),
            )
            msg.hasRemoteImeKeyInject() -> {
                currentApp = msg.remoteImeKeyInject.appInfo.appPackage
                onCurrentAppUpdated?.invoke(currentApp)
            }
        }
    }

    private fun resumeStarted(error: Throwable?) {
        startedDeferred?.let { d ->
            startedDeferred = null
            if (error != null) d.completeExceptionally(error) else d.complete(Unit)
        }
    }
}
