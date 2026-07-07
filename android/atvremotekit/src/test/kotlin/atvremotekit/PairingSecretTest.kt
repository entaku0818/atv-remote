package atvremotekit

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

/**
 * Same inputs and expected digest as ATVRemoteKitTests.swift's
 * PairingSecretTests.testMatchesPythonReference — cross-verifies the Kotlin
 * port against both the Swift implementation and the original Python
 * reference (androidtvremote2).
 */
class PairingSecretTest {
    private val clientModulus = byteArrayOf(
        0xC3.toByte(), 0xA1.toByte(), 0xB2.toByte(), 0xD4.toByte(), 0xE5.toByte(), 0xF6.toByte(), 0x07, 0x18,
        0x29, 0x3A, 0x4B, 0x5C, 0x6D, 0x7E, 0x8F.toByte(), 0x90.toByte(),
    )
    private val clientExponent = byteArrayOf(0x01, 0x00, 0x01)
    private val serverModulus = byteArrayOf(
        0xF1.toByte(), 0xE2.toByte(), 0xD3.toByte(), 0xC4.toByte(), 0xB5.toByte(), 0xA6.toByte(), 0x97.toByte(),
        0x88.toByte(), 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88.toByte(), 0x99.toByte(), 0x00,
        0xAA.toByte(), 0xBB.toByte(),
    )
    private val serverExponent = byteArrayOf(0x01, 0x00, 0x01)

    @Test
    fun matchesPythonReference() {
        val secret = PairingSecret.compute(clientModulus, clientExponent, serverModulus, serverExponent, "A47F21")
        assertEquals(
            "a405bc6a88414e6d08d8bb4997a3d3db6eb1c3575da9af0a34289e8cb11d2427",
            secret.joinToString("") { "%02x".format(it) },
        )
    }

    @Test
    fun wrongCodeThrows() {
        assertFailsWith<ATVError.InvalidPairingCode> {
            PairingSecret.compute(clientModulus, clientExponent, serverModulus, serverExponent, "3A7F21")
        }
    }
}
