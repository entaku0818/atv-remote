package atvremotekit

import com.google.protobuf.MessageLite
import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import remote.Remotemessage.RemoteMessage

class RemoteSessionTest {
    @Test
    fun immediateReplyDuringConnectIsNotLost() = runBlocking {
        val transport = FakeConnection()
        transport.onConnect = {
            val reply = RemoteMessage.newBuilder().apply {
                remoteStartBuilder.started = true
            }.build()
            transport.onMessage?.invoke(reply.toByteArray())
        }
        val session = RemoteSession(transport)
        withTimeout(2_000) { session.connect() }
        assertTrue(session.isOn)
        session.disconnect()
        assertTrue(transport.cancelled)
    }

    @Test
    fun immediateCloseFailsInsteadOfWaitingForever() = runBlocking {
        val transport = FakeConnection()
        transport.onConnect = { transport.onClosed?.invoke(null) }
        assertFailsWith<ATVError.ConnectionClosed> {
            withTimeout(2_000) { RemoteSession(transport).connect() }
        }
        assertTrue(transport.cancelled)
    }

    @Test
    fun connectFailureClosesTransport() = runBlocking {
        val transport = FakeConnection()
        transport.onConnect = { throw IllegalStateException("TLS failed") }
        assertFailsWith<IllegalStateException> { RemoteSession(transport).connect() }
        assertTrue(transport.cancelled)
    }

    @Test
    fun cancellationClosesTransportWhenTvDoesNotReply() = runBlocking {
        val transport = FakeConnection()
        assertFailsWith<TimeoutCancellationException> {
            withTimeout(100) { RemoteSession(transport).connect() }
        }
        assertTrue(transport.cancelled)
    }

    private class FakeConnection : RemoteConnection {
        override var onMessage: ((ByteArray) -> Unit)? = null
        override var onClosed: ((Throwable?) -> Unit)? = null
        var onConnect: () -> Unit = {}
        var cancelled = false
        override fun connect() = onConnect()
        override fun send(message: MessageLite) = Unit
        override fun cancel() { cancelled = true }
    }
}
