package atvremotekit

import java.io.File
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.Signature
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.interfaces.RSAPublicKey
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Date

/**
 * The client's TLS identity (RSA key + self-signed certificate).
 * The Android TV learns this certificate during pairing and trusts it
 * afterwards, so the same identity must be reused across connections.
 *
 * Unlike ATVRemoteKit's Swift ClientIdentity (which has to parse DER to pull
 * modulus/exponent out of a SecKey), JVM's RSAPublicKey exposes both as
 * BigInteger directly.
 */
class ClientIdentity(val privateKey: PrivateKey, val certificate: X509Certificate) {

    val publicKey: RSAPublicKey get() = certificate.publicKey as RSAPublicKey

    /** Modulus and exponent of this client's public key (leading zeros stripped). */
    fun publicKeyModulusExponent(): Pair<ByteArray, ByteArray> = modulusExponent(publicKey)

    companion object {
        const val DEFAULT_COMMON_NAME = "atvremote"

        /** Loads the identity from disk, generating key + certificate on first use. */
        fun loadOrCreate(
            privateKeyFile: File,
            certificateFile: File,
            commonName: String = DEFAULT_COMMON_NAME,
        ): ClientIdentity {
            if (privateKeyFile.exists() && certificateFile.exists()) {
                return load(privateKeyFile, certificateFile)
            }
            val identity = create(commonName)
            save(identity, privateKeyFile, certificateFile)
            return identity
        }

        fun load(privateKeyFile: File, certificateFile: File): ClientIdentity {
            val privateKey = KeyFactory.getInstance("RSA")
                .generatePrivate(PKCS8EncodedKeySpec(privateKeyFile.readBytes()))
            val certificate = certificateFile.inputStream().use { input ->
                CertificateFactory.getInstance("X.509").generateCertificate(input) as X509Certificate
            }
            return ClientIdentity(privateKey, certificate)
        }

        fun create(commonName: String = DEFAULT_COMMON_NAME): ClientIdentity {
            val keyPairGenerator = KeyPairGenerator.getInstance("RSA")
            keyPairGenerator.initialize(2048)
            val keyPair = keyPairGenerator.generateKeyPair()
            val certDer = SelfSignedCertificate.make(keyPair, commonName)
            val certificate = certDer.inputStream().use { input ->
                CertificateFactory.getInstance("X.509").generateCertificate(input) as X509Certificate
            }
            return ClientIdentity(keyPair.private, certificate)
        }

        fun save(identity: ClientIdentity, privateKeyFile: File, certificateFile: File) {
            privateKeyFile.parentFile?.mkdirs()
            privateKeyFile.writeBytes(identity.privateKey.encoded)
            certificateFile.writeBytes(identity.certificate.encoded)
        }

        fun modulusExponent(publicKey: RSAPublicKey): Pair<ByteArray, ByteArray> =
            magnitude(publicKey.modulus) to magnitude(publicKey.publicExponent)

        /** BigInteger.toByteArray() is two's-complement and may carry a leading sign byte; strip it. */
        private fun magnitude(value: BigInteger): ByteArray = ASN1.stripLeadingZeros(value.toByteArray())
    }
}

/**
 * Builds a self-signed X.509 v3 certificate mirroring what androidtvremote2
 * generates (CN, 10-year validity, CA basic constraint, SAN). Ported from
 * ATVRemoteKit's SelfSignedCertificate (ClientIdentity.swift).
 */
object SelfSignedCertificate {
    fun make(keyPair: KeyPair, commonName: String): ByteArray {
        val publicKey = keyPair.public as RSAPublicKey

        val sha256WithRSA = ASN1.sequence(
            listOf(ASN1.oid(byteArrayOf(0x2A, 0x86.toByte(), 0x48, 0x86.toByte(), 0xF7.toByte(), 0x0D, 0x01, 0x01, 0x0B)), ASN1.oidNull()),
        )
        val rsaEncryption = ASN1.sequence(
            listOf(ASN1.oid(byteArrayOf(0x2A, 0x86.toByte(), 0x48, 0x86.toByte(), 0xF7.toByte(), 0x0D, 0x01, 0x01, 0x01)), ASN1.oidNull()),
        )
        val name = ASN1.sequence(
            listOf(
                ASN1.set(
                    listOf(
                        ASN1.sequence(
                            listOf(
                                ASN1.oid(byteArrayOf(0x55, 0x04, 0x03)), // commonName
                                ASN1.utf8String(commonName),
                            ),
                        ),
                    ),
                ),
            ),
        )
        val now = Date()
        val validity = ASN1.sequence(
            listOf(
                ASN1.utcTime(Date(now.time - 86_400_000L)),
                ASN1.utcTime(Date(now.time + 10L * 365 * 86_400_000L)),
            ),
        )
        val publicKeyPKCS1 = ASN1.sequence(
            listOf(
                ASN1.integer(magnitude = publicKey.modulus.toByteArray()),
                ASN1.integer(magnitude = publicKey.publicExponent.toByteArray()),
            ),
        )
        val spki = ASN1.sequence(listOf(rsaEncryption, ASN1.bitString(publicKeyPKCS1)))
        val extensions = ASN1.contextConstructed(
            3,
            ASN1.sequence(
                listOf(
                    ASN1.sequence(
                        listOf(
                            ASN1.oid(byteArrayOf(0x55, 0x1D, 0x13)), // basicConstraints CA:TRUE, pathLen 0
                            ASN1.octetString(ASN1.sequence(listOf(ASN1.boolean(true), ASN1.integer(0)))),
                        ),
                    ),
                    ASN1.sequence(
                        listOf(
                            ASN1.oid(byteArrayOf(0x55, 0x1D, 0x11)), // subjectAltName dNSName
                            ASN1.octetString(
                                ASN1.sequence(listOf(ASN1.contextPrimitive(2, commonName.toByteArray(Charsets.UTF_8)))),
                            ),
                        ),
                    ),
                ),
            ),
        )
        val tbs = ASN1.sequence(
            listOf(
                ASN1.contextConstructed(0, ASN1.integer(2)), // version v3
                ASN1.integer(1000),
                sha256WithRSA,
                name,
                validity,
                name,
                spki,
                extensions,
            ),
        )
        val signature = Signature.getInstance("SHA256withRSA").run {
            initSign(keyPair.private)
            update(tbs)
            sign()
        }
        return ASN1.sequence(listOf(tbs, sha256WithRSA, ASN1.bitString(signature)))
    }
}
