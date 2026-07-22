/// Exact RDF string identity over the source Unicode scalar sequence.
///
/// Swift `String` equality applies Unicode canonical equivalence. RDF term
/// identity does not: two lexical forms are equal only when their character
/// sequences are equal. UTF-8 is a canonical, order-preserving encoding of
/// valid Swift strings, so it provides exact equality, hashing, and ordering
/// without materializing scalar or byte arrays.
enum DatabaseStringIdentity {
    static func equal(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }

    static func less(_ lhs: String, _ rhs: String) -> Bool {
        var left = lhs.utf8.makeIterator()
        var right = rhs.utf8.makeIterator()
        while true {
            switch (left.next(), right.next()) {
            case (.none, .none):
                return false
            case (.none, .some):
                return true
            case (.some, .none):
                return false
            case (.some(let leftByte), .some(let rightByte)):
                if leftByte != rightByte {
                    return leftByte < rightByte
                }
            }
        }
    }

    static func hash(_ value: String, into hasher: inout Hasher) {
        hasher.combine(value.utf8.count)

        var word: UInt64 = 0
        var shift: UInt64 = 0
        for byte in value.utf8 {
            word |= UInt64(byte) << shift
            shift += 8
            if shift == 64 {
                hasher.combine(word)
                word = 0
                shift = 0
            }
        }
        if shift != 0 {
            hasher.combine(word)
        }
    }

    static func equal(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.some(let left), .some(let right)):
            return equal(left, right)
        default:
            return false
        }
    }

    static func hash(_ value: String?, into hasher: inout Hasher) {
        switch value {
        case .none:
            hasher.combine(false)
        case .some(let value):
            hasher.combine(true)
            hash(value, into: &hasher)
        }
    }

    static func equalASCIICaseInsensitive(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        var left = lhs.utf8.makeIterator()
        var right = rhs.utf8.makeIterator()
        while true {
            switch (left.next(), right.next()) {
            case (.none, .none):
                return true
            case (.some(let leftByte), .some(let rightByte)):
                guard asciiFold(leftByte) == asciiFold(rightByte) else {
                    return false
                }
            default:
                return false
            }
        }
    }

    static func lessASCIICaseInsensitive(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        var left = lhs.utf8.makeIterator()
        var right = rhs.utf8.makeIterator()
        while true {
            switch (left.next(), right.next()) {
            case (.none, .none):
                return false
            case (.none, .some):
                return true
            case (.some, .none):
                return false
            case (.some(let leftByte), .some(let rightByte)):
                let foldedLeft = asciiFold(leftByte)
                let foldedRight = asciiFold(rightByte)
                if foldedLeft != foldedRight {
                    return foldedLeft < foldedRight
                }
            }
        }
    }

    static func hashASCIICaseInsensitive(
        _ value: String,
        into hasher: inout Hasher
    ) {
        hasher.combine(value.utf8.count)

        var word: UInt64 = 0
        var shift: UInt64 = 0
        for byte in value.utf8 {
            word |= UInt64(asciiFold(byte)) << shift
            shift += 8
            if shift == 64 {
                hasher.combine(word)
                word = 0
                shift = 0
            }
        }
        if shift != 0 {
            hasher.combine(word)
        }
    }

    static func equalASCIICaseInsensitive(
        _ lhs: String?,
        _ rhs: String?
    ) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.some(let left), .some(let right)):
            return equalASCIICaseInsensitive(left, right)
        default:
            return false
        }
    }

    static func hashASCIICaseInsensitive(
        _ value: String?,
        into hasher: inout Hasher
    ) {
        switch value {
        case .none:
            hasher.combine(false)
        case .some(let value):
            hasher.combine(true)
            hashASCIICaseInsensitive(value, into: &hasher)
        }
    }

    static func canonicalASCIILowercase(_ value: String) -> String {
        guard value.utf8.contains(where: { $0 >= 65 && $0 <= 90 }) else {
            return value
        }

        return String(unsafeUninitializedCapacity: value.utf8.count) { buffer in
            var index = 0
            for byte in value.utf8 {
                buffer[index] = asciiFold(byte)
                index += 1
            }
            return index
        }
    }

    private static func asciiFold(_ byte: UInt8) -> UInt8 {
        byte >= 65 && byte <= 90 ? byte + 32 : byte
    }
}
