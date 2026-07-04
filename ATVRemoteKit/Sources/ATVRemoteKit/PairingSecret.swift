import CryptoKit
import Foundation

/// Computes the pairing secret: SHA-256 over client modulus, client exponent,
/// server modulus, server exponent and the last 2 bytes of the 6-hex-digit
/// pairing code. The first byte of the digest must equal the code's first byte.
enum PairingSecret {
    static func codeBytes(from pairingCode: String) throws -> Data {
        let code = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 6 else {
            throw ATVError.invalidPairingCode("code must be exactly 6 hex characters")
        }
        var bytes = Data()
        var iterator = code.makeIterator()
        while let high = iterator.next(), let low = iterator.next() {
            guard let h = high.hexDigitValue, let l = low.hexDigitValue else {
                throw ATVError.invalidPairingCode("code must be hex")
            }
            bytes.append(UInt8(h << 4 | l))
        }
        return bytes
    }

    static func compute(
        clientModulus: Data, clientExponent: Data,
        serverModulus: Data, serverExponent: Data,
        pairingCode: String
    ) throws -> Data {
        let code = try codeBytes(from: pairingCode)
        var hasher = SHA256()
        hasher.update(data: clientModulus)
        hasher.update(data: clientExponent)
        hasher.update(data: serverModulus)
        hasher.update(data: serverExponent)
        hasher.update(data: code.dropFirst())
        let digest = Data(hasher.finalize())
        guard digest.first == code.first else {
            throw ATVError.invalidPairingCode("code check failed — wrong code or wrong certificates")
        }
        return digest
    }
}
