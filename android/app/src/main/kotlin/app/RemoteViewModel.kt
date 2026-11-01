package app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import atvremotekit.ClientIdentity
import atvremotekit.PairingSession
import atvremotekit.RemoteSession
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
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

    private var operation: Job? = null
    private var identity: ClientIdentity? = null
    private var remote: RemoteSession? = null
    private var pairing: PairingSession? = null

    fun connect() {
        disconnect()
        identity = null
        pairingCode = ""
        currentApp = ""
        deviceDescription = ""
        phase = RemotePhase.Connecting
        operation = scope.launch {
            try {
                val id = withContext(Dispatchers.IO) {
                    ClientIdentity.loadOrCreate(File(identityDir, "key.der"), File(identityDir, "cert.der"))
                }
                identity = id
                connectRemote(id)
            } catch (e: TimeoutCancellationException) {
                phase = RemotePhase.Failed("TVが応答しません。同じネットワークとTVの電源を確認してください")
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Not paired yet (or the TV rejected the certificate) — start pairing.
                startPairing()
            }
        }
    }

    private suspend fun connectRemote(identity: ClientIdentity) {
        val session = RemoteSession(host, identity = identity)
        remote = session
        session.onCurrentAppUpdated = { app ->
            scope.launch { if (remote === session) currentApp = app }
        }
        session.onClosed = { error ->
            scope.launch {
                if (remote === session && phase == RemotePhase.Connected) {
                    remote = null
                    session.disconnect()
                    phase = RemotePhase.Failed("TVとの接続が切れました。再接続してください: ${error?.message ?: "接続終了"}")
                }
            }
        }
        try {
            withTimeout(15_000) { session.connect() }
        } catch (error: Exception) {
            if (remote === session) remote = null
            session.disconnect()
            throw error
        }
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
        val session = PairingSession(host, clientName = "ATVRemote Android", identity = id)
        pairing = session
        try {
            withTimeout(15_000) { session.start() }
            phase = RemotePhase.PairingCodeRequired
        } catch (e: CancellationException) {
            session.cancel()
            if (pairing === session) pairing = null
            if (e !is TimeoutCancellationException) throw e
            phase = RemotePhase.Failed("TVにコードを表示できませんでした。TVの電源とネットワークを確認してください")
        } catch (e: Exception) {
            session.cancel()
            if (pairing === session) pairing = null
            phase = RemotePhase.Failed("ペアリング開始に失敗: ${e.message}")
        }
    }

    fun submitPairingCode() {
        if (phase != RemotePhase.PairingCodeRequired) return
        val session = pairing ?: return
        val id = identity ?: return
        phase = RemotePhase.Pairing
        operation = scope.launch {
            try {
                withTimeout(15_000) { session.finish(pairingCode) }
                pairing = null
                connectRemote(id)
            } catch (e: CancellationException) {
                session.cancel()
                if (pairing === session) pairing = null
                if (e !is TimeoutCancellationException) throw e
                phase = RemotePhase.Failed("TVの応答がありません。再接続してください")
            } catch (e: Exception) {
                session.cancel()
                pairing = null
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
        operation?.cancel()
        operation = null
        pairing?.cancel()
        pairing = null
        val previous = remote
        remote = null
        previous?.disconnect()
        phase = RemotePhase.Idle
    }

    fun close() {
        disconnect()
        scope.cancel()
    }
}
