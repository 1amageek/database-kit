import DatabaseTypes

/// Decodes validated wire text while preserving the borrowed byte boundary.
enum DatabaseWireTextDecoder {
    static func isValid(_ bytes: ByteString) -> Bool {
        bytes.withUnsafeBytes { isValid($0) }
    }

    static func isValid(_ bytes: UnsafeRawBufferPointer) -> Bool {
        var index = 0
        while index < bytes.count {
            let first = bytes[index]
            let scalarByteCount: Int

            switch first {
            case 0x00...0x7F:
                scalarByteCount = 1

            case 0xC2...0xDF:
                guard index + 1 < bytes.count,
                      isContinuation(bytes[index + 1]) else {
                    return false
                }
                scalarByteCount = 2

            case 0xE0...0xEF:
                guard index + 2 < bytes.count else {
                    return false
                }
                let second = bytes[index + 1]
                guard isContinuation(second),
                      isContinuation(bytes[index + 2]),
                      first != 0xE0 || second >= 0xA0,
                      first != 0xED || second < 0xA0 else {
                    return false
                }
                scalarByteCount = 3

            case 0xF0...0xF4:
                guard index + 3 < bytes.count else {
                    return false
                }
                let second = bytes[index + 1]
                guard isContinuation(second),
                      isContinuation(bytes[index + 2]),
                      isContinuation(bytes[index + 3]),
                      first != 0xF0 || second >= 0x90,
                      first != 0xF4 || second <= 0x8F else {
                    return false
                }
                scalarByteCount = 4

            default:
                return false
            }

            index += scalarByteCount
        }
        return true
    }

    static func decode(_ bytes: ByteString) -> String? {
        bytes.withUnsafeBytes { decode($0) }
    }

    static func decode(
        _ bytes: UnsafeRawBufferPointer
    ) -> String? {
        var value = String()
        value.reserveCapacity(bytes.count)

        var index = 0
        while index < bytes.count {
            let first = bytes[index]
            let scalarValue: UInt32
            let scalarByteCount: Int

            switch first {
            case 0x00...0x7F:
                scalarValue = UInt32(first)
                scalarByteCount = 1

            case 0xC2...0xDF:
                guard index + 1 < bytes.count else { return nil }
                let second = bytes[index + 1]
                guard isContinuation(second) else { return nil }
                scalarValue = UInt32(first & 0x1F) << 6
                    | UInt32(second & 0x3F)
                scalarByteCount = 2

            case 0xE0...0xEF:
                guard index + 2 < bytes.count else { return nil }
                let second = bytes[index + 1]
                let third = bytes[index + 2]
                guard isContinuation(second),
                      isContinuation(third),
                      first != 0xE0 || second >= 0xA0,
                      first != 0xED || second < 0xA0 else {
                    return nil
                }
                scalarValue = UInt32(first & 0x0F) << 12
                    | UInt32(second & 0x3F) << 6
                    | UInt32(third & 0x3F)
                scalarByteCount = 3

            case 0xF0...0xF4:
                guard index + 3 < bytes.count else { return nil }
                let second = bytes[index + 1]
                let third = bytes[index + 2]
                let fourth = bytes[index + 3]
                guard isContinuation(second),
                      isContinuation(third),
                      isContinuation(fourth),
                      first != 0xF0 || second >= 0x90,
                      first != 0xF4 || second <= 0x8F else {
                    return nil
                }
                scalarValue = UInt32(first & 0x07) << 18
                    | UInt32(second & 0x3F) << 12
                    | UInt32(third & 0x3F) << 6
                    | UInt32(fourth & 0x3F)
                scalarByteCount = 4

            default:
                return nil
            }

            guard let scalar = Unicode.Scalar(scalarValue) else {
                return nil
            }
            value.unicodeScalars.append(scalar)
            index += scalarByteCount
        }
        return value
    }

    private static func isContinuation(_ byte: UInt8) -> Bool {
        byte >= 0x80 && byte <= 0xBF
    }
}
