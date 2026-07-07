package atvremotekit

import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Minimal DER encoder — just enough to build a self-signed X.509 certificate.
 * Ported from ATVRemoteKit's ASN1.swift; unlike the Swift version this only
 * needs the encoding half, since JVM's [java.security.interfaces.RSAPublicKey]
 * already exposes modulus/exponent as BigInteger without DER parsing.
 */
object ASN1 {
    fun tlv(tag: Int, content: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(tag)
        out.write(lengthBytes(content.size))
        out.write(content)
        return out.toByteArray()
    }

    private fun lengthBytes(length: Int): ByteArray {
        if (length < 0x80) return byteArrayOf(length.toByte())
        var len = length
        val bytes = ArrayDeque<Byte>()
        while (len > 0) {
            bytes.addFirst((len and 0xFF).toByte())
            len = len ushr 8
        }
        return byteArrayOf((0x80 or bytes.size).toByte()) + bytes.toByteArray()
    }

    fun sequence(parts: List<ByteArray>): ByteArray = tlv(0x30, concat(parts))

    fun set(parts: List<ByteArray>): ByteArray = tlv(0x31, concat(parts))

    fun integer(value: Int): ByteArray {
        require(value >= 0)
        var v = value
        val bytes = ArrayDeque<Byte>()
        do {
            bytes.addFirst((v and 0xFF).toByte())
            v = v ushr 8
        } while (v > 0)
        if (bytes.first().toInt() and 0x80 != 0) bytes.addFirst(0)
        return tlv(0x02, bytes.toByteArray())
    }

    /** INTEGER from magnitude bytes (prepends 0x00 if the high bit is set). */
    fun integer(magnitude: ByteArray): ByteArray {
        var body = stripLeadingZeros(magnitude)
        if (body.isNotEmpty() && (body[0].toInt() and 0x80 != 0)) {
            body = byteArrayOf(0) + body
        } else if (body.isEmpty()) {
            body = byteArrayOf(0)
        }
        return tlv(0x02, body)
    }

    fun oid(bytes: ByteArray): ByteArray = tlv(0x06, bytes)

    fun oidNull(): ByteArray = byteArrayOf(0x05, 0x00)

    fun boolean(value: Boolean): ByteArray = byteArrayOf(0x01, 0x01, if (value) 0xFF.toByte() else 0x00)

    fun utf8String(value: String): ByteArray = tlv(0x0C, value.toByteArray(Charsets.UTF_8))

    fun utcTime(date: Date): ByteArray {
        val fmt = SimpleDateFormat("yyMMddHHmmss'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return tlv(0x17, fmt.format(date).toByteArray(Charsets.US_ASCII))
    }

    fun bitString(data: ByteArray): ByteArray = tlv(0x03, byteArrayOf(0x00) + data)

    fun octetString(data: ByteArray): ByteArray = tlv(0x04, data)

    /** Constructed context-specific tag, e.g. [0], [3]. */
    fun contextConstructed(number: Int, content: ByteArray): ByteArray = tlv(0xA0 or number, content)

    /** Primitive context-specific tag, e.g. dNSName [2] in a GeneralName. */
    fun contextPrimitive(number: Int, content: ByteArray): ByteArray = tlv(0x80 or number, content)

    private fun concat(parts: List<ByteArray>): ByteArray {
        val out = ByteArrayOutputStream()
        parts.forEach { out.write(it) }
        return out.toByteArray()
    }

    fun stripLeadingZeros(data: ByteArray): ByteArray {
        var start = 0
        while (start < data.size - 1 && data[start] == 0.toByte()) start++
        return data.copyOfRange(start, data.size)
    }
}
