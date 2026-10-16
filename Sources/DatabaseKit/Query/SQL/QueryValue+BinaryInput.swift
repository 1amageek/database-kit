import DatabaseTypes

extension QueryValue {
    /// Forms immutable bytes from BYTEA hexadecimal or traditional escape input.
    public static func binary(sqlLexicalForm: borrowing Substring,
                              maximumUTF8Count: UInt64) throws(QueryValueError) -> QueryValue {
        let count = UInt64(sqlLexicalForm.utf8.count)
        guard count <= maximumUTF8Count else {
            throw .resourceLimit(resource: "binary input bytes", actual: count, maximum: maximumUTF8Count)
        }
        let outputCount = try BinaryInput.decode(sqlLexicalForm, emit: { _ in })
        // Validation and exact measurement precede the sole output allocation.
        // ByteString owns this buffer; the pointer never escapes its initializer.
        // The immutable replay writes exactly outputCount disjoint UInt8 slots,
        // bounded by input UTF-8 count. Input and newly allocated output cannot alias;
        // ByteString.copying owns initialized-count tracking and failure cleanup.
        // Each emitted byte consumes input, so counts fit Int; raw UInt8 stores
        // require alignment one and cover exactly 0..<outputCount without rebinding.
        let bytes = try ByteString.copying(count: outputCount) {
            (buffer: UnsafeMutableRawBufferPointer) throws(QueryValueError) in
            var offset = 0
            _ = try BinaryInput.decode(sqlLexicalForm) { byte in
                buffer[offset] = byte
                offset += 1
            }
        }
        return .primitive(.bytes(bytes))
    }

    private struct BinaryInput {
        let bytes: Substring.UTF8View
        var index: String.Index
        var offset: UInt64 = 0

        init(_ text: borrowing Substring) { bytes = text.utf8; index = bytes.startIndex }
        var current: UInt8? { index == bytes.endIndex ? nil : bytes[index] }
        var next: UInt8? {
            guard index != bytes.endIndex else { return nil }
            let next = bytes.index(after: index)
            return next == bytes.endIndex ? nil : bytes[next]
        }
        mutating func advance() { bytes.formIndex(after: &index); offset += 1 }
        func invalid(_ reason: String) -> QueryValueError { .invalidBinary(offset: offset, reason: reason) }

        static func decode(_ text: borrowing Substring,
                           emit: (UInt8) -> Void) throws(QueryValueError) -> Int {
            var input = Self(text)
            var count = 0
            if input.current == 92, input.next == 120 {
                input.advance(); input.advance()
                while let byte = input.current {
                    if byte == 32 || byte == 9 || byte == 10 || byte == 13 { input.advance(); continue }
                    guard let high = hex(byte) else { throw input.invalid("Invalid BYTEA hexadecimal digit") }
                    input.advance()
                    guard let byte = input.current, let low = hex(byte) else {
                        throw input.invalid("Incomplete BYTEA hexadecimal byte")
                    }
                    input.advance()
                    emit((high << 4) | low)
                    count += 1
                }
            } else {
                while let byte = input.current {
                    input.advance()
                    if byte != 92 { emit(byte); count += 1; continue }
                    guard let byte = input.current else { throw input.invalid("Incomplete BYTEA escape") }
                    input.advance()
                    if byte == 92 { emit(92); count += 1; continue }
                    guard (48...51).contains(byte), let second = input.current, (48...55).contains(second) else {
                        throw input.invalid("Invalid BYTEA octal escape")
                    }
                    input.advance()
                    guard let third = input.current, (48...55).contains(third) else {
                        throw input.invalid("Incomplete BYTEA octal escape")
                    }
                    input.advance()
                    emit((byte - 48) * 64 + (second - 48) * 8 + (third - 48))
                    count += 1
                }
            }
            return count
        }

        private static func hex(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 48...57: return byte - 48
            case 65...70: return byte - 55
            case 97...102: return byte - 87
            default: return nil
            }
        }
    }
}
