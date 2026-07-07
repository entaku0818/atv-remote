package atvremotekit

import kotlin.test.Test
import kotlin.test.assertEquals

/** Mirrors ATVRemoteKitTests.swift's CertificateTests. */
class ClientIdentityTest {
    @Test
    fun generatedCertificateRoundTrips() {
        val identity = ClientIdentity.create("atvremote-test")
        val (modulus, exponent) = identity.publicKeyModulusExponent()
        assertEquals(256, modulus.size, "2048-bit modulus without leading zeros")
        assertEquals(listOf<Byte>(0x01, 0x00, 0x01), exponent.toList())
        // A self-signed cert must verify against its own public key.
        identity.certificate.verify(identity.certificate.publicKey)
    }
}
