import DatabaseKit
import DatabaseTypes
import Testing

@Suite("SQL lexical value construction")
struct SQLLexicalValueConstructionTests {
    @Test("Exact numeric input retains lexical scale, signs, exponents and radix integers")
    func numericForms() throws {
        let cases: [(String, ExactDecimal, Int32)] = [
            ("1.2300", .init(coefficient: 123, scale: 2), 4),
            ("1.2300e2", .init(coefficient: 123, scale: 0), 2),
            ("1.2300e-2", .init(coefficient: 123, scale: 4), 6),
            ("-0.000", .init(coefficient: 0, scale: 0), 3),
            (" \t+.50e+2\r\n", .init(coefficient: 5, scale: -1), 0),
            ("1_000.230_0", .init(coefficient: 100023, scale: 2), 4),
            ("0x_7f_ff", .init(coefficient: 32767, scale: 0), 0),
            ("-0o_7_7", .init(coefficient: -63, scale: 0), 0),
            ("0b10_10", .init(coefficient: 10, scale: 0), 0),
        ]
        for (text, expected, scale) in cases {
            let numeric = try QueryNumericValue(sqlLexicalForm: text[...], maximumUTF8Count: UInt64(text.utf8.count))
            #expect(numeric.value == expected)
            #expect(numeric.displayScale == scale)
        }
        let owner = "prefix1.2300suffix"
        let input = owner.dropFirst(6).dropLast(6)
        #expect(try QueryNumericValue(sqlLexicalForm: input, maximumUTF8Count: 6).displayScale == 4)
    }

    @Test("Numeric range and malformed lexical failures stay distinct")
    func numericFailuresAndBounds() throws {
        let maximum = String(repeating: "9", count: 38)
        #expect(try QueryNumericValue(sqlLexicalForm: maximum[...], maximumUTF8Count: 38).displayScale == 0)
        #expect(try QueryNumericValue(sqlLexicalForm: "1e-16383", maximumUTF8Count: 8).displayScale == 16383)
        #expect(try QueryNumericValue(sqlLexicalForm: "1e131071", maximumUTF8Count: 8).value.scale == -131071)
        for text in [String(repeating: "9", count: 39), "1e-16384", "1e131072", "1e9999999999999999999999"] {
            #expect(throws: QueryValueError.numericOutOfRange) {
                try QueryNumericValue(sqlLexicalForm: text[...], maximumUTF8Count: 1024)
            }
        }
        for text in ["", "+", ".", "1e", "1e+", "1e_2", "1._2", "1_.2", "1__2", "0x__1", "0b2", "0o8", "NaN", "Infinity", "-Infinity", "1 2", "\u{a0}1"] {
            do {
                _ = try QueryNumericValue(sqlLexicalForm: text[...], maximumUTF8Count: 1024)
                Issue.record("Malformed numeric input succeeded: \(text)")
            } catch {
                guard case .invalidNumeric = error else { Issue.record("Expected lexical failure: \(error)"); continue }
            }
        }
        #expect(throws: QueryValueError.invalidNumeric(offset: 3, reason: "Repeated numeric decimal point")) {
            try QueryNumericValue(sqlLexicalForm: "1.2.3", maximumUTF8Count: 5)
        }
    }

    @Test("UUID lexical variants produce the same canonical primitive")
    func uuidForms() throws {
        let expected = QueryValue.primitive(.uuid(UUID(canonicalString: "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11")!))
        for text in ["a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11", "A0EEBC99-9C0B-4EF8-BB6D-6BB9BD380A11",
                     "{a0eebc999c0b4ef8bb6d6bb9bd380a11}", "a0ee-bc99-9c0b-4ef8-bb6d-6bb9-bd38-0a11"] {
            #expect(try QueryValue.uuid(sqlLexicalForm: text[...], maximumUTF8Count: 64) == expected)
        }
        for text in ["bad", "{a0eebc999c0b4ef8bb6d6bb9bd380a11", "a0eebc999c0b4ef8bb6d6bb9bd380a11}",
                     "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a1x", "a0eebc999c0b4ef8bb6d6bb9bd380a11-",
                     " a0eebc999c0b4ef8bb6d6bb9bd380a11", "a0-eebc999c0b4ef8bb6d6bb9bd380a11"] {
            do { _ = try QueryValue.uuid(sqlLexicalForm: text[...], maximumUTF8Count: 64); Issue.record("Invalid UUID succeeded") }
            catch { guard case .invalidUUID = error else { Issue.record("Expected UUID lexical failure"); continue } }
        }
    }

    @Test("BYTEA hex and traditional escape input retain exact bytes")
    func binaryForms() throws {
        #expect(try QueryValue.binary(sqlLexicalForm: #"\x00 FF 80"#, maximumUTF8Count: 64) == .primitive(.bytes([0, 255, 128])))
        #expect(try QueryValue.binary(sqlLexicalForm: "\\x 00\tFF\n80\r", maximumUTF8Count: 12) == .primitive(.bytes([0, 255, 128])))
        #expect(try QueryValue.binary(sqlLexicalForm: #"\001\377\\A"#, maximumUTF8Count: 64) == .primitive(.bytes([1, 255, 92, 65])))
        #expect(try QueryValue.binary(sqlLexicalForm: "é😀", maximumUTF8Count: 6) == .primitive(.bytes(ByteString(utf8: "é😀"))))
        #expect(try QueryValue.binary(sqlLexicalForm: #"\x"#, maximumUTF8Count: 2) == .primitive(.bytes([])))
        #expect(try QueryValue.binary(sqlLexicalForm: "", maximumUTF8Count: 0) == .primitive(.bytes([])))
        for text in [#"\x0"#, #"\x0 0"#, #"\xzz"#, "\\x00\u{b}ff", "\\x00\u{c}ff", "\\", #"\400"#, #"\08a"#, #"\12"#, #"\q"#] {
            do { _ = try QueryValue.binary(sqlLexicalForm: text[...], maximumUTF8Count: 64); Issue.record("Invalid BYTEA succeeded") }
            catch { guard case .invalidBinary = error else { Issue.record("Expected BYTEA lexical failure"); continue } }
        }
    }

    @Test("All lexical constructors enforce exact original input byte limits")
    func inputByteLimits() throws {
        #expect(try QueryNumericValue(sqlLexicalForm: " 1.20 ", maximumUTF8Count: 6).displayScale == 2)
        #expect(throws: QueryValueError.resourceLimit(resource: "numeric input bytes", actual: 6, maximum: 5)) {
            try QueryNumericValue(sqlLexicalForm: " 1.20 ", maximumUTF8Count: 5)
        }
        let uuid = "a0eebc999c0b4ef8bb6d6bb9bd380a11"
        _ = try QueryValue.uuid(sqlLexicalForm: uuid[...], maximumUTF8Count: 32)
        #expect(throws: QueryValueError.resourceLimit(resource: "UUID input bytes", actual: 32, maximum: 31)) {
            try QueryValue.uuid(sqlLexicalForm: uuid[...], maximumUTF8Count: 31)
        }
        #expect(try QueryValue.binary(sqlLexicalForm: "é", maximumUTF8Count: 2) == .primitive(.bytes([0xc3, 0xa9])))
        #expect(throws: QueryValueError.resourceLimit(resource: "binary input bytes", actual: 2, maximum: 1)) {
            try QueryValue.binary(sqlLexicalForm: "é", maximumUTF8Count: 1)
        }
    }

    @Test("CHAR and VARCHAR descriptors enforce the same bounds for NULL and strings")
    func characterDescriptorBounds() {
        for type: DataType in [.char(length: nil), .varchar(length: nil), .char(length: 1), .varchar(length: 1),
                               .char(length: 10_485_760), .varchar(length: 10_485_760)] {
            #expect(QueryValueValidator.accepts(.primitive(.null), type: .sql(type)))
            #expect(QueryValueValidator.accepts(.primitive(.string("x")), type: .sql(type)))
        }
        for length in [-1, 0, 10_485_761, Int.max] {
            for type: DataType in [.char(length: length), .varchar(length: length)] {
                #expect(!QueryValueValidator.accepts(.primitive(.null), type: .sql(type)))
                #expect(!QueryValueValidator.accepts(.primitive(.string("x")), type: .sql(type)))
            }
        }
        #expect(QueryValueValidator.accepts(.primitive(.null), type: .sql(.binary(length: Int.max))))
    }
}
