package app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import atvremotekit.ClientIdentity
import atvremotekit.PairingSession
import atvremotekit.RemoteSession
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import remote.Remotemessage.RemoteKeyCode

sealed class RemotePhase {
    data object Idle : RemotePhase()
    data object Connecting : RemotePhase()
    data object PairingCodeRequired : RemotePhase()
    data object Pairing : RemotePhase()
    data object Connected : RemotePhase()
    data class Failed(val message: String) : RemotePhase()
}

/**
 * Mirrors RemoteViewModel.swift's phase state machine on top of the same
 * atvremotekit session types the CLI uses. A plain class (not
 * androidx.lifecycle.ViewModel`) instantiated with `remember` from Compose,
 * matching the scope of iOS's `@StateObject` — this is a PoC screen, not a
 * component that needs to survive process death.
 */
class RemoteViewModel(private val host: String, private val identityDir: File) {
    private val scope = CoroutineScope(Dispatchers.Main.immediate + SupervisorJob())

    var phase: RemotePhase by mutableStateOf(RemotePhase.Idle)
        private set
    var pairingCode: String by mutableStateOf("")
    var deviceDescription: String by mutableStateOf("")
        private set
    var currentApp: String by mutableStateOf("")
        private set

    private var identity: ClientIdentity? = null
    private var remote: RemoteSession? = null
    private var pairing: PairingSession? = null

    fun connect() {
        phase = RemotePhase.Connecting
        scope.launch {
            try {
                val id = ClientIdentity.loadOrCreate(File(identityDir, "key.der"), File(identityDir, "cert.der"))
                identity = id
                connectRemote(id)
            } catch (e: Exception) {
                // Not paired yet (or the TV rejected the certificate) — start pairing.
                startPairing()
            }
        }
    }

    private suspend fun connectRemote(identity: ClientIdentity) {
        val session = RemoteSession(host, identity = identity)
        session.onCurrentAppUpdated = { app -> currentApp = app }
        session.connect()
        remote = session
        session.deviceInfo?.let { info ->
            deviceDescription = "${info.vendor} ${info.model} (sw ${info.version})"
        }
        phase = RemotePhase.Connected
    }

    private suspend fun startPairing() {
        val id = identity
        if (id == null) {
            phase = RemotePhase.Failed("証明書の準備に失敗しました")
            return
        }
        try {
            val session = PairingSession(host, clientName = "ATVRemote Android", identity = id)
            pairing = session
            session.start()
            phase = RemotePhase.PairingCodeRequired
        } catch (e: Exception) {
            phase = RemotePhase.Failed("ペアリング開始に失敗: ${e.message}")
        }
    }

    fun submitPairingCode() {
        val session = pairing ?: return
        val id = identity ?: return
        phase = RemotePhase.Pairing
        scope.launch {
            try {
                session.finish(pairingCode)
                pairing = null
                connectRemote(id)
            } catch (e: Exception) {
                phase = RemotePhase.Failed("ペアリング失敗: ${e.message}")
            }
        }
    }

    fun send(key: RemoteKeyCode) {
        remote?.sendKey(key)
    }

    fun launchAppLink(url: String) {
        remote?.launchApp(url)
    }

    fun disconnect() {
        pairing?.cancel()
        remote?.disconnect()
        remote = null
    }

    fun close() {
        disconnect()
        scope.cancel()
    }
}
