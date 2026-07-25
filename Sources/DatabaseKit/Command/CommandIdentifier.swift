/// A canonical application-command identifier.
///
/// Identifiers consist of dot-separated ASCII name segments. Each segment
/// starts with a letter and continues with letters or digits.
public struct CommandIdentifier: Sendable, Hashable, Comparable {
    public static let maximumUTF8Bytes = 256

    public let rawValue: String

    public init(
        _ rawValue: String
    ) throws(CommandIdentifierError) {
        let bytes = rawValue.utf8
        guard !bytes.isEmpty else {
            throw .empty
        }
        guard bytes.count <= Self.maximumUTF8Bytes else {
            throw .tooLong(
                actualUTF8Bytes: bytes.count,
                maximumUTF8Bytes: Self.maximumUTF8Bytes
            )
        }

        var beginsSegment = true
        for byte in bytes {
            if beginsSegment {
                guard Self.isASCIILetter(byte) else {
                    if byte == 0x2E {
                        throw .adjacentSeparator
                    }
                    throw .invalidStart(byte)
                }
                beginsSegment = false
                continue
            }
            if byte == 0x2E {
                beginsSegment = true
                continue
            }
            guard Self.isASCIILetter(byte) || Self.isASCIIDigit(byte) else {
                throw .invalidByte(byte)
            }
        }
        guard !beginsSegment else {
            throw .trailingSeparator
        }
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.utf8.lexicographicallyPrecedes(rhs.rawValue.utf8)
    }

    private static func isASCIILetter(_ byte: UInt8) -> Bool {
        (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
    }
}
