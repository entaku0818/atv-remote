package atvremotekit

import com.google.polo.wire.protobuf.PoloProto.OuterMessage
import com.google.polo.wire.protobuf.PoloProto.Options
import com.google.protobuf.ByteString
import java.security.interfaces.RSAPublicKey
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Pairing protocol with an Android TV (port 6467). Ported from
 * PairingSession.swift.
 *
 * Flow: PairingRequest -> (ack) -> Options -> (options) -> Configuration ->
 * (configuration_ack: TV shows a 6-digit code) -> Secret -> (secret_ack).
 */
class PairingSession(
    host: String,
    port: Int = 6467,
    private val clientName: String,
    private val identity: ClientIdentity,
) {
    private val connection = ProtobufConnection(host, port, identity)
    private var codeDisplayed: CompletableDeferred<Unit>? = null
    private var finished: CompletableDeferred<Unit>? = null

    /** Connects and drives pairing until the TV displays the 6-digit code. */
    suspend fun start() {
        connection.onMessage = { handle(it) }
        connection.onClosed = { error -> fail(ATVError.ConnectionClosed(error?.message ?: "closed")) }
        withContext(Dispatchers.IO) { connection.connect() }

        val deferred = CompletableDeferred<Unit>()
        codeDisplayed = deferred
        send(
            newMessage().apply {
                pairingRequestBuilder.clientName = clientName
                pairingRequestBuilder.serviceName = "atvremote"
            },
        )
        deferred.await()
    }

    /** Sends the secret computed from the code the user read off the TV screen. */
    suspend fun finish(code: String) {
        val serverCert = connection.serverCertificate
            ?: throw ATVError.PairingFailed("no server certificate captured")
        val serverKey = serverCert.publicKey as RSAPublicKey
        val (serverModulus, serverExponent) = ClientIdentity.modulusExponent(serverKey)
        val (clientModulus, clientExponent) = identity.publicKeyModulusExponent()
        val secret = PairingSecret.compute(clientModulus, clientExponent, serverModulus, serverExponent, code)

        val deferred = CompletableDeferred<Unit>()
        finished = deferred
        send(newMessage().apply { secretBuilder.secret = ByteString.copyFrom(secret) })
        deferred.await()
        connection.cancel()
    }

    fun cancel() = connection.cancel()

    // MARK: Internals

    private fun newMessage(): OuterMessage.Builder =
        OuterMessage.newBuilder().setProtocolVersion(2).setStatus(OuterMessage.Status.STATUS_OK)

    private fun send(builder: OuterMessage.Builder) = connection.send(builder.build())

    private fun handle(raw: ByteArray) {
        val msg = try {
            OuterMessage.parseFrom(raw)
        } catch (e: Exception) {
            fail(ATVError.PairingFailed("cannot parse OuterMessage"))
            return
        }
        if (msg.status != OuterMessage.Status.STATUS_OK) {
            fail(ATVError.PairingFailed("TV returned status ${msg.status}"))
            return
        }
        when {
            msg.hasPairingRequestAck() -> send(
                newMessage().apply {
                    optionsBuilder.preferredRole = Options.RoleType.ROLE_TYPE_INPUT
                    optionsBuilder.addInputEncodings(
                        Options.Encoding.newBuilder()
                            .setType(Options.Encoding.EncodingType.ENCODING_TYPE_HEXADECIMAL)
                            .setSymbolLength(6),
                    )
                },
            )
            msg.hasOptions() -> send(
                newMessage().apply {
                    configurationBuilder.clientRole = Options.RoleType.ROLE_TYPE_INPUT
                    configurationBuilder.encodingBuilder
                        .setType(Options.Encoding.EncodingType.ENCODING_TYPE_HEXADECIMAL)
                        .setSymbolLength(6)
                },
            )
            msg.hasConfigurationAck() -> resumeCodeDisplayed(null)
            msg.hasSecretAck() -> resumeFinished(null)
            else -> fail(ATVError.PairingFailed("unhandled message"))
        }
    }

    private fun resumeCodeDisplayed(error: Throwable?) {
        codeDisplayed?.let { d ->
            codeDisplayed = null
            if (error != null) d.completeExceptionally(error) else d.complete(Unit)
        }
    }

    private fun resumeFinished(error: Throwable?) {
        finished?.let { d ->
            finished = null
            if (error != null) d.completeExceptionally(error) else d.complete(Unit)
        }
    }

    private fun fail(error: Throwable) {
        resumeCodeDisplayed(error)
        resumeFinished(error)
    }
}
