import Foundation

/// Protobuf varint length-prefix framing used by the Android TV remote protocol.
enum Varint {
    static func encode(_ value: Int) -> Data {
        var v = UInt64(value)
        var out = Data()
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }

    /// Decodes a varint at the start of `data`.
    /// Returns (value, bytesConsumed) or nil if more bytes are needed.
    static func decode(_ data: Data) -> (value: Int, consumed: Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var consumed = 0
        for byte in data {
            result |= UInt64(byte & 0x7F) << shift
            consumed += 1
            if byte & 0x80 == 0 {
                return (Int(result), consumed)
            }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }
}

/// Accumulates a TCP byte stream and yields complete varint-prefixed messages.
struct MessageFramer {
    private var buffer = Data()

    mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var messages: [Data] = []
        while let (length, consumed) = Varint.decode(buffer),
              buffer.count >= consumed + length {
            let start = buffer.startIndex + consumed
            messages.append(Data(buffer[start..<start + length]))
            buffer.removeFirst(consumed + length)
        }
        return messages
    }

    static func frame(_ message: Data) -> Data {
        Varint.encode(message.count) + message
    }
}
