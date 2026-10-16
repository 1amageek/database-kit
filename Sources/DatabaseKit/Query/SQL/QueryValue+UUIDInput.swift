import DatabaseTypes

extension QueryValue {
    /// Forms the existing UUID primitive from PostgreSQL UUID lexical input.
    public static func uuid(sqlLexicalForm: borrowing Substring,
                            maximumUTF8Count: UInt64) throws(QueryValueError) -> QueryValue {
        let count = UInt64(sqlLexicalForm.utf8.count)
        guard count <= maximumUTF8Count else {
            throw .resourceLimit(resource: "UUID input bytes", actual: count, maximum: maximumUTF8Count)
        }
        var input = UUIDInput(sqlLexicalForm)
        let braces = input.current == 123
        if braces { input.advance() }
        var high: UInt64 = 0
        var low: UInt64 = 0
        for position in 0..<16 {
            guard let first = input.current, let upper = UUIDInput.hex(first) else {
                throw input.invalid("Invalid UUID hexadecimal digit")
            }
            input.advance()
            guard let second = input.current, let lower = UUIDInput.hex(second) else {
                throw input.invalid("Invalid UUID hexadecimal digit")
            }
            input.advance()
            let byte = UInt64((upper << 4) | lower)
            if position < 8 { high = (high << 8) | byte }
            else { low = (low << 8) | byte }
            if position < 15, position.isMultiple(of: 2) == false, input.current == 45 {
                input.advance()
            }
        }
        if braces {
            guard input.current == 125 else { throw input.invalid("Missing UUID closing brace") }
            input.advance()
        }
        guard input.current == nil else { throw input.invalid("Trailing UUID input") }
        return .primitive(.uuid(UUID(high: high, low: low)))
    }

    private struct UUIDInput {
        let bytes: Substring.UTF8View
        var index: String.Index
        var offset: UInt64 = 0

        init(_ text: borrowing Substring) { bytes = text.utf8; index = bytes.startIndex }
        var current: UInt8? { index == bytes.endIndex ? nil : bytes[index] }
        mutating func advance() { bytes.formIndex(after: &index); offset += 1 }
        func invalid(_ reason: String) -> QueryValueError { .invalidUUID(offset: offset, reason: reason) }
        static func hex(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 48...57: return byte - 48
            case 65...70: return byte - 55
            case 97...102: return byte - 87
            default: return nil
            }
        }
    }
}
