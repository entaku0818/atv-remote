import Foundation

/// Minimal DER encoder/decoder — just enough to build a self-signed X.509
/// certificate and read modulus/exponent out of a PKCS#1 RSAPublicKey.
enum ASN1 {
    // MARK: Encoding

    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        out.append(lengthBytes(content.count))
        out.append(content)
        return out
    }

    private static func lengthBytes(_ length: Int) -> Data {
        if length < 0x80 { return Data([UInt8(length)]) }
        var len = length
        var bytes: [UInt8] = []
        while len > 0 {
            bytes.insert(UInt8(len & 0xFF), at: 0)
            len >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    static func sequence(_ parts: [Data]) -> Data {
        tlv(0x30, parts.reduce(Data(), +))
    }

    static func set(_ parts: [Data]) -> Data {
        tlv(0x31, parts.reduce(Data(), +))
    }

    static func integer(_ value: Int) -> Data {
        precondition(value >= 0)
        var v = value
        var bytes: [UInt8] = []
        repeat {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        } while v > 0
        if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return tlv(0x02, Data(bytes))
    }

    /// INTEGER from magnitude bytes (prepends 0x00 if the high bit is set).
    static func integer(magnitude: Data) -> Data {
        var body = magnitude
        while body.count > 1, body.first == 0 { body.removeFirst() }
        if let first = body.first, first & 0x80 != 0 {
            body.insert(0, at: body.startIndex)
        }
        return tlv(0x02, body)
    }

    static func oid(_ bytes: [UInt8]) -> Data {
        tlv(0x06, Data(bytes))
    }

    static func null() -> Data { Data([0x05, 0x00]) }

    static func boolean(_ value: Bool) -> Data {
        Data([0x01, 0x01, value ? 0xFF : 0x00])
    }

    static func utf8String(_ value: String) -> Data {
        tlv(0x0C, Data(value.utf8))
    }

    static func ia5String(_ value: String) -> Data {
        tlv(0x16, Data(value.utf8))
    }

    static func utcTime(_ date: Date) -> Data {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyMMddHHmmss'Z'"
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return tlv(0x17, Data(fmt.string(from: date).utf8))
    }

    static func bitString(_ data: Data) -> Data {
        tlv(0x03, Data([0x00]) + data)
    }

    static func octetString(_ data: Data) -> Data {
        tlv(0x04, data)
    }

    /// Constructed context-specific tag, e.g. [0], [3].
    static func contextConstructed(_ number: UInt8, _ content: Data) -> Data {
        tlv(0xA0 | number, content)
    }

    /// Primitive context-specific tag, e.g. dNSName [2] in a GeneralName.
    static func contextPrimitive(_ number: UInt8, _ content: Data) -> Data {
        tlv(0x80 | number, content)
    }

    // MARK: Decoding (just enough for PKCS#1 RSAPublicKey)

    struct Reader {
        private let data: Data
        private var index: Data.Index

        init(_ data: Data) {
            self.data = data
            self.index = data.startIndex
        }

        mutating func readTLV() -> (tag: UInt8, content: Data)? {
            guard index < data.endIndex else { return nil }
            let tag = data[index]
            index = data.index(after: index)
            guard index < data.endIndex else { return nil }
            var length = Int(data[index])
            index = data.index(after: index)
            if length & 0x80 != 0 {
                let count = length & 0x7F
                length = 0
                for _ in 0..<count {
                    guard index < data.endIndex else { return nil }
                    length = length << 8 | Int(data[index])
                    index = data.index(after: index)
                }
            }
            guard data.distance(from: index, to: data.endIndex) >= length else { return nil }
            let content = Data(data[index..<data.index(index, offsetBy: length)])
            index = data.index(index, offsetBy: length)
            return (tag, content)
        }
    }

    /// Parses a PKCS#1 RSAPublicKey (SEQUENCE { INTEGER modulus, INTEGER exponent })
    /// and returns both magnitudes with leading zero bytes stripped.
    static func parsePKCS1RSAPublicKey(_ der: Data) -> (modulus: Data, exponent: Data)? {
        var outer = Reader(der)
        guard let seq = outer.readTLV(), seq.tag == 0x30 else { return nil }
        var inner = Reader(seq.content)
        guard let mod = inner.readTLV(), mod.tag == 0x02,
              let exp = inner.readTLV(), exp.tag == 0x02 else { return nil }
        return (stripLeadingZeros(mod.content), stripLeadingZeros(exp.content))
    }

    private static func stripLeadingZeros(_ data: Data) -> Data {
        var d = data
        while d.count > 1, d.first == 0 { d.removeFirst() }
        return d
    }
}
