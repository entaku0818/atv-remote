package atvremotekit

import com.google.protobuf.MessageLite
import java.io.IOException
import java.net.Socket
import java.security.cert.X509Certificate
import java.util.concurrent.Executors
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509KeyManager
import javax.net.ssl.X509TrustManager

/**
 * TLS connection to an Android TV that sends/receives varint-length-prefixed
 * protobuf messages. Presents the client identity and accepts the TV's
 * self-signed server certificate (capturing it for the pairing secret).
 *
 * Ported from ProtobufConnection.swift. Framing is handled by protobuf-java's
 * own delimited I/O (writeDelimitedTo/parseDelimitedFrom), so there is no
 * Kotlin equivalent of Varint.swift/MessageFramer.
 */
class ProtobufConnection(private val host: String, private val port: Int, private val identity: ClientIdentity) {
    private val executor = Executors.newSingleThreadExecutor { r -> Thread(r, "atvremotekit-connection").apply { isDaemon = true } }

    @Volatile private var socket: SSLSocket? = null

    @Volatile var serverCertificate: X509Certificate? = null
        private set

    var onMessage: ((ByteArray) -> Unit)? = null
    var onClosed: ((Throwable?) -> Unit)? = null

    fun connect() {
        val keyManager = SingleIdentityKeyManager(identity)
        val trustManager = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String) {}

            // The TV uses a self-signed certificate; trust is established by pairing, not by CA validation.
            override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String) {
                serverCertificate = chain.firstOrNull()
            }

            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        }

        val context = SSLContext.getInstance("TLS")
        context.init(arrayOf<javax.net.ssl.KeyManager>(keyManager), arrayOf<javax.net.ssl.TrustManager>(trustManager), null)
        val sslSocket = context.socketFactory.createSocket(host, port) as SSLSocket
        sslSocket.enabledProtocols = arrayOf("TLSv1.3", "TLSv1.2")
        sslSocket.tcpNoDelay = true
        sslSocket.startHandshake()
        socket = sslSocket
        executor.execute { receiveLoop(sslSocket) }
    }

    private fun receiveLoop(sslSocket: SSLSocket) {
        try {
            val input = sslSocket.inputStream
            while (true) {
                val message = readDelimitedMessage(input) ?: break
                onMessage?.invoke(message)
            }
            onClosed?.invoke(ATVError.ConnectionClosed("EOF"))
        } catch (e: IOException) {
            if (!sslSocket.isClosed) onClosed?.invoke(ATVError.ConnectionClosed(e.message ?: "closed"))
        }
    }

    /**
     * Reads one varint-length-prefixed message, or null on a clean EOF before
     * any bytes of the next message arrive. [CodedInputStream.readRawVarint32]
     * is the same public primitive protobuf-java's own parseDelimitedFrom
     * uses; we can't call parseDelimitedFrom directly here because this
     * transport is shared by two different message types (OuterMessage,
     * RemoteMessage).
     */
    private fun readDelimitedMessage(input: java.io.InputStream): ByteArray? {
        val firstByte = input.read()
        if (firstByte == -1) return null
        val size = com.google.protobuf.CodedInputStream.readRawVarint32(firstByte, input)
        val bytes = ByteArray(size)
        var offset = 0
        while (offset < size) {
            val read = input.read(bytes, offset, size - offset)
            if (read == -1) throw IOException("unexpected EOF mid-message")
            offset += read
        }
        return bytes
    }

    fun send(message: MessageLite) {
        val s = socket ?: return
        synchronized(s) {
            try {
                message.writeDelimitedTo(s.outputStream)
                s.outputStream.flush()
            } catch (_: IOException) {
                // Surfaced to the caller via the receive loop's onClosed callback.
            }
        }
    }

    fun cancel() {
        try {
            socket?.close()
        } catch (_: IOException) {
        }
        executor.shutdown()
    }
}

/** Always presents the same client certificate/key, regardless of which alias the server requests. */
private class SingleIdentityKeyManager(private val identity: ClientIdentity) : X509KeyManager {
    private val alias = "atvremote-client"

    override fun getClientAliases(keyType: String?, issuers: Array<out java.security.Principal>?) = arrayOf(alias)
    override fun chooseClientAlias(keyType: Array<out String>?, issuers: Array<out java.security.Principal>?, socket: Socket?) = alias
    override fun getServerAliases(keyType: String?, issuers: Array<out java.security.Principal>?): Array<String>? = null
    override fun chooseServerAlias(keyType: String?, issuers: Array<out java.security.Principal>?, socket: Socket?): String? = null
    override fun getCertificateChain(alias: String?): Array<X509Certificate> = arrayOf(identity.certificate)
    override fun getPrivateKey(alias: String?) = identity.privateKey
}
