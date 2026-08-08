enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case string(String)
    case number(String)
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case (.bool(let left), .bool(let right)): left == right
        case (.string(let left), .string(let right)): left == right
        case (.number(let left), .number(let right)): left == right
        case (.array(let left), .array(let right)): left == right
        case (.object(let left), .object(let right)):
            left.count == right.count && zip(left, right).allSatisfy {
                $0.key == $1.key && $0.value == $1.value
            }
        default: false
        }
    }
}

struct JSONParser: Sendable {
    let maximumBytes: Int
    let maximumDepth: Int
    let maximumCollectionCount: Int

    func parse(_ text: String) throws(SchemaJSONError) -> JSONValue {
        let bytes = Array(text.utf8)
        guard bytes.count <= maximumBytes else {
            throw .inputTooLarge(actual: bytes.count, maximum: maximumBytes)
        }
        var scanner = Scanner(
            bytes: bytes,
            maximumDepth: maximumDepth,
            maximumCollectionCount: maximumCollectionCount
        )
        let value = try scanner.parseValue(depth: 0)
        scanner.skipWhitespace()
        guard scanner.isAtEnd else {
            throw scanner.error("Trailing JSON input")
        }
        return value
    }
}

private extension JSONParser {
    struct Scanner {
        let bytes: [UInt8]
        let maximumDepth: Int
        let maximumCollectionCount: Int
        var offset = 0

        var isAtEnd: Bool { offset == bytes.count }

        mutating func parseValue(depth: Int) throws(SchemaJSONError) -> JSONValue {
            guard depth <= maximumDepth else {
                throw .nestingTooDeep(maximum: maximumDepth)
            }
            skipWhitespace()
            guard let byte = peek() else { throw error("Expected JSON value") }
            switch byte {
            case 0x6E:
                try consumeLiteral("null")
                return .null
            case 0x74:
                try consumeLiteral("true")
                return .bool(true)
            case 0x66:
                try consumeLiteral("false")
                return .bool(false)
            case 0x22:
                return .string(try parseString())
            case 0x5B:
                return .array(try parseArray(depth: depth + 1))
            case 0x7B:
                return .object(try parseObject(depth: depth + 1))
            case 0x2D, 0x30...0x39:
                return .number(try parseNumber())
            default:
                throw error("Invalid JSON value")
            }
        }

        mutating func parseArray(depth: Int) throws(SchemaJSONError) -> [JSONValue] {
            try consume(0x5B)
            skipWhitespace()
            if consumeIf(0x5D) { return [] }
            var values: [JSONValue] = []
            while true {
                guard values.count < maximumCollectionCount else {
                    throw .collectionTooLarge(
                        path: "JSON array",
                        actual: values.count + 1,
                        maximum: maximumCollectionCount
                    )
                }
                values.append(try parseValue(depth: depth))
                skipWhitespace()
                if consumeIf(0x5D) { return values }
                try consume(0x2C)
                skipWhitespace()
            }
        }

        mutating func parseObject(
            depth: Int
        ) throws(SchemaJSONError) -> [(key: String, value: JSONValue)] {
            try consume(0x7B)
            skipWhitespace()
            if consumeIf(0x7D) { return [] }
            var fields: [(key: String, value: JSONValue)] = []
            var keys: Set<String> = []
            while true {
                guard fields.count < maximumCollectionCount else {
                    throw .collectionTooLarge(
                        path: "JSON object",
                        actual: fields.count + 1,
                        maximum: maximumCollectionCount
                    )
                }
                guard peek() == 0x22 else {
                    throw error("JSON object keys must be strings")
                }
                let keyOffset = offset
                let key = try parseString()
                guard keys.insert(key).inserted else {
                    throw .duplicateKey(key: key, byteOffset: keyOffset)
                }
                skipWhitespace()
                try consume(0x3A)
                fields.append((key, try parseValue(depth: depth)))
                skipWhitespace()
                if consumeIf(0x7D) { return fields }
                try consume(0x2C)
                skipWhitespace()
            }
        }

        mutating func parseString() throws(SchemaJSONError) -> String {
            try consume(0x22)
            var output: [UInt8] = []
            while let byte = peek() {
                offset += 1
                switch byte {
                case 0x22:
                    guard let string = String(bytes: output, encoding: .utf8) else {
                        throw error("String contains invalid UTF-8")
                    }
                    return string
                case 0x00...0x1F:
                    throw error("Unescaped control character in string")
                case 0x5C:
                    try appendEscape(to: &output)
                default:
                    output.append(byte)
                }
            }
            throw error("Unterminated JSON string")
        }

        mutating func appendEscape(
            to output: inout [UInt8]
        ) throws(SchemaJSONError) {
            guard let escaped = peek() else { throw error("Incomplete escape") }
            offset += 1
            switch escaped {
            case 0x22, 0x5C, 0x2F: output.append(escaped)
            case 0x62: output.append(0x08)
            case 0x66: output.append(0x0C)
            case 0x6E: output.append(0x0A)
            case 0x72: output.append(0x0D)
            case 0x74: output.append(0x09)
            case 0x75:
                let first = try parseHexQuad()
                let scalarValue: UInt32
                if (0xD800...0xDBFF).contains(first) {
                    guard consumeIf(0x5C), consumeIf(0x75) else {
                        throw error("High surrogate is not followed by a low surrogate")
                    }
                    let second = try parseHexQuad()
                    guard (0xDC00...0xDFFF).contains(second) else {
                        throw error("Invalid low surrogate")
                    }
                    scalarValue = 0x10000
                        + (UInt32(first - 0xD800) << 10)
                        + UInt32(second - 0xDC00)
                } else {
                    guard !(0xDC00...0xDFFF).contains(first) else {
                        throw error("Unexpected low surrogate")
                    }
                    scalarValue = UInt32(first)
                }
                guard let scalar = UnicodeScalar(scalarValue) else {
                    throw error("Invalid Unicode scalar")
                }
                output.append(contentsOf: String(scalar).utf8)
            default:
                throw error("Unknown string escape")
            }
        }

        mutating func parseHexQuad() throws(SchemaJSONError) -> UInt16 {
            var value: UInt16 = 0
            for _ in 0..<4 {
                guard let byte = peek(), let digit = hexadecimalValue(byte) else {
                    throw error("Invalid Unicode escape")
                }
                offset += 1
                value = (value << 4) | UInt16(digit)
            }
            return value
        }

        mutating func parseNumber() throws(SchemaJSONError) -> String {
            let start = offset
            _ = consumeIf(0x2D)
            if consumeIf(0x30) {
                if let next = peek(), (0x30...0x39).contains(next) {
                    throw error("JSON number has a leading zero")
                }
            } else {
                try consumeDigits()
            }
            if consumeIf(0x2E) { try consumeDigits() }
            if let byte = peek(), byte == 0x65 || byte == 0x45 {
                offset += 1
                if let sign = peek(), sign == 0x2B || sign == 0x2D {
                    offset += 1
                }
                try consumeDigits()
            }
            return String(decoding: bytes[start..<offset], as: UTF8.self)
        }

        mutating func consumeDigits() throws(SchemaJSONError) {
            let start = offset
            while let byte = peek(), (0x30...0x39).contains(byte) {
                offset += 1
            }
            guard start != offset else { throw error("Expected decimal digit") }
        }

        mutating func consumeLiteral(_ literal: StaticString) throws(SchemaJSONError) {
            for byte in literal.withUTF8Buffer({ Array($0) }) {
                try consume(byte)
            }
        }

        mutating func consume(_ expected: UInt8) throws(SchemaJSONError) {
            guard peek() == expected else {
                throw error("Expected JSON token")
            }
            offset += 1
        }

        mutating func consumeIf(_ expected: UInt8) -> Bool {
            guard peek() == expected else { return false }
            offset += 1
            return true
        }

        func peek() -> UInt8? {
            offset < bytes.count ? bytes[offset] : nil
        }

        mutating func skipWhitespace() {
            while let byte = peek(),
                  byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 {
                offset += 1
            }
        }

        func error(_ message: String) -> SchemaJSONError {
            .invalidSyntax(message: message, byteOffset: offset)
        }

        func hexadecimalValue(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 0x30...0x39: byte - 0x30
            case 0x41...0x46: byte - 0x41 + 10
            case 0x61...0x66: byte - 0x61 + 10
            default: nil
            }
        }
    }
}

enum JSONWriter {
    static func encode(_ value: JSONValue) -> String {
        var output = ""
        append(value, to: &output)
        return output
    }

    private static func append(_ value: JSONValue, to output: inout String) {
        switch value {
        case .null: output += "null"
        case .bool(let value): output += value ? "true" : "false"
        case .string(let value): appendQuoted(value, to: &output)
        case .number(let value): output += value
        case .array(let values):
            output += "["
            for (index, value) in values.enumerated() {
                if index > 0 { output += "," }
                append(value, to: &output)
            }
            output += "]"
        case .object(let fields):
            output += "{"
            for (index, field) in fields.enumerated() {
                if index > 0 { output += "," }
                appendQuoted(field.key, to: &output)
                output += ":"
                append(field.value, to: &output)
            }
            output += "}"
        }
    }

    private static func appendQuoted(_ value: String, to output: inout String) {
        let hex: [Character] = Array("0123456789abcdef")
        output += "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: output += "\\\""
            case 0x5C: output += "\\\\"
            case 0x08: output += "\\b"
            case 0x0C: output += "\\f"
            case 0x0A: output += "\\n"
            case 0x0D: output += "\\r"
            case 0x09: output += "\\t"
            case 0x00...0x1F:
                output += "\\u00"
                output.append(hex[Int((scalar.value >> 4) & 0xF)])
                output.append(hex[Int(scalar.value & 0xF)])
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }
}

struct JSONObject {
    private let fields: [String: JSONValue]
    let path: String

    init(_ value: JSONValue, path: String) throws(SchemaJSONError) {
        guard case .object(let pairs) = value else {
            throw .typeMismatch(path: path, expected: "an object")
        }
        self.fields = Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, $0.value) })
        self.path = path
    }

    func required(_ name: String) throws(SchemaJSONError) -> JSONValue {
        guard let value = fields[name] else {
            throw .missingField(path: child(name))
        }
        return value
    }

    func optional(_ name: String) -> JSONValue? { fields[name] }

    func validateKeys(_ allowed: Set<String>) throws(SchemaJSONError) {
        if let unknown = fields.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw .unknownField(path: child(unknown))
        }
    }

    func child(_ name: String) -> String {
        path.isEmpty ? name : "\(path).\(name)"
    }
}

extension JSONValue {
    func string(path: String) throws(SchemaJSONError) -> String {
        guard case .string(let value) = self else {
            throw .typeMismatch(path: path, expected: "a string")
        }
        return value
    }

    func bool(path: String) throws(SchemaJSONError) -> Bool {
        guard case .bool(let value) = self else {
            throw .typeMismatch(path: path, expected: "a boolean")
        }
        return value
    }

    func number(path: String) throws(SchemaJSONError) -> String {
        guard case .number(let value) = self else {
            throw .typeMismatch(path: path, expected: "a number")
        }
        return value
    }

    func array(path: String) throws(SchemaJSONError) -> [JSONValue] {
        guard case .array(let value) = self else {
            throw .typeMismatch(path: path, expected: "an array")
        }
        return value
    }
}
