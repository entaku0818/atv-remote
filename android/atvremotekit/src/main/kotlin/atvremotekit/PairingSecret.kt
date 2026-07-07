package atvremotekit

import java.security.MessageDigest

/**
 * Computes the pairing secret: SHA-256 over client modulus, client exponent,
 * server modulus, server exponent and the last 2 bytes of the 6-hex-digit
 * pairing code. The first byte of the digest must equal the code's first byte.
 *
 * Ported from PairingSecret.swift; the test vector in PairingSecretTest.kt is
 * shared verbatim with ATVRemoteKitTests.swift's PairingSecretTests for
 * cross-language verification.
 */
object PairingSecret {
    fun codeBytes(pairingCode: String): ByteArray {
        val code = pairingCode.trim().uppercase()
        if (code.length != 6) {
            throw ATVError.InvalidPairingCode("code must be exactly 6 hex characters")
        }
        val bytes = ByteArray(3)
        for (i in 0..2) {
            val high = Character.digit(code[i * 2], 16)
            val low = Character.digit(code[i * 2 + 1], 16)
            if (high < 0 || low < 0) {
                throw ATVError.InvalidPairingCode("code must be hex")
            }
            bytes[i] = ((high shl 4) or low).toByte()
        }
        return bytes
    }

    fun compute(
        clientModulus: ByteArray,
        clientExponent: ByteArray,
        serverModulus: ByteArray,
        serverExponent: ByteArray,
        pairingCode: String,
    ): ByteArray {
        val code = codeBytes(pairingCode)
        val digest = MessageDigest.getInstance("SHA-256").run {
            update(clientModulus)
            update(clientExponent)
            update(serverModulus)
            update(serverExponent)
            update(code, 1, code.size - 1)
            digest()
        }
        if (digest[0] != code[0]) {
            throw ATVError.InvalidPairingCode("code check failed — wrong code or wrong certificates")
        }
        return digest
    }
}
