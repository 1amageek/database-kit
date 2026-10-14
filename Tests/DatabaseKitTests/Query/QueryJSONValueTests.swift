import DatabaseKit
import DatabaseTypes
import Testing

@Suite("Query JSON values")
struct QueryJSONValueTests {
    private func limits(bytes: UInt64 = 100_000, nodes: UInt64 = 1000,
                        depth: UInt64 = 100, elements: UInt64 = 1000) -> QueryValueLimits {
        QueryValueLimits(maximumRetainedBytes: bytes, maximumTotalNodes: nodes,
                         maximumNestingDepth: depth, maximumCollectionElements: elements)
    }

    private func lexical(_ text: String) throws(QueryValueError) -> QueryJSONValue {
        try QueryJSONValue(bytes: ByteString(utf8: text), limits: limits())
    }

    private func binary(_ text: String) throws(QueryValueError) -> QueryJSONBValue {
        try QueryJSONBValue(json: lexical(text), limits: limits())
    }

    @Test("Lexical JSON preserves original bytes, duplicate members and owner")
    func lexicalOwnership() throws {
        let bytes = ByteString(utf8: " \n{\"b\":1.00, \"a\":null, \"b\":2}\t")
        let json = try QueryJSONValue(bytes: bytes, limits: limits())
        #expect(json.bytes == bytes)
        #expect(json.bytes.withUnsafeBytes { actual in
            bytes.withUnsafeBytes { original in actual.baseAddress == original.baseAddress }
        })
        #expect(try json.measure().nodeCount == 4)
        #expect(try json.measure().collectionElementCount == 3)
    }

    @Test("Lexical JSON admits all JSON root kinds without numeric conversion")
    func lexicalRootKinds() throws {
        for text in ["null", "true", "false", "\"text\"", "[]", "{}", "1e999999999999999999999999"] {
            #expect(try lexical(text).bytes == ByteString(utf8: text))
        }
        #expect(try binary("null").root == .null)
    }

    @Test("Malformed lexical forms and trailing input are rejected")
    func malformedJSON() {
        for text in ["", " ", "null null", "01", "+1", "1.", "1e", "1e+", "-.1",
                     "[1,]", "{\"x\":1,}", "{x:1}", "{\"x\" 1}", "[", "\"open", "\"\\x\"", "\"\\uZZZZ\"", "\"\n\""] {
            #expect(throws: QueryValueError.self) { try lexical(text) }
        }
    }

    @Test("Raw UTF-8 rejects overlong, surrogate, truncated and out of range sequences")
    func invalidUTF8() {
        for sequence: [UInt8] in [[0xC0, 0xAF], [0xED, 0xA0, 0x80], [0xF4, 0x90, 0x80, 0x80], [0xE2, 0x82], [0x80]] {
            let bytes = ByteString([34] + sequence + [34])
            #expect(throws: QueryValueError.self) { try QueryJSONValue(bytes: bytes, limits: limits()) }
        }
    }

    @Test("Lexical Unicode escapes remain lexical while JSONB enforces Unicode semantics")
    func unicodeEscapeValidation() throws {
        for text in ["\"\\u0000\"", "\"\\ud800\"", "\"\\udc00\"", "\"\\ud800\\u0041\""] {
            let json = try lexical(text)
            #expect(throws: QueryValueError.self) { try QueryJSONBValue(json: json, limits: limits()) }
        }
        #expect(try binary("\"\\ud83d\\ude00\"").root == .string("😀"))
        #expect(try binary("\"é\\n\\t\\b\\f\\r\\/\\\\\\\"\"").root == .string("é\n\t\u{8}\u{C}\r/\\\""))
    }

    @Test("JSONB object keys are ordered by UTF-8 length then unsigned bytes")
    func canonicalKeyOrdering() throws {
        let value = try binary("{\"é\":3,\"aa\":2,\"z\":1,\"b\":4}")
        guard case .object(let members) = value.root else { Issue.record("Expected object"); return }
        #expect(members.map(\.key) == ["b", "z", "aa", "é"])
        #expect(try QueryJSONBValue(root: value.root, limits: limits()) == value)
    }

    @Test("Duplicate decoded keys retain the last value")
    func lastDuplicateWins() throws {
        let value = try binary("{\"a\":1,\"\\u0061\":2.00}")
        let number = try QueryNumericValue(value: ExactDecimal(coefficient: 2, scale: 0), displayScale: 2)
        #expect(value.root == (try QueryJSONBNode.object([QueryJSONBMember(key: "a", value: .number(number))], limits: limits())))
    }

    @Test("JSONB identity distinguishes canonically equivalent Unicode byte sequences")
    func unicodeByteIdentity() throws {
        let first = "é", second = "e\u{301}"
        #expect(first == second)
        #expect(QueryJSONBNode.string(first) != .string(second))
        #expect(Set([QueryJSONBNode.string(first), .string(second)]).count == 2)
        let value = try binary("{\"é\":1,\"e\\u0301\":2}")
        guard case .object(let members) = value.root else { Issue.record("Expected object"); return }
        #expect(members.count == 2)
        #expect(members[0].key.utf8.elementsEqual(first.utf8))
        #expect(members[1].key.utf8.elementsEqual(second.utf8))
    }

    @Test("JSONB numbers retain fractional display scale separately from canonical scale")
    func numericDisplayScale() throws {
        let fixtures: [(String, Int128, Int32, Int32)] = [
            ("1.2300", 123, 2, 4), ("1.2300e2", 123, 0, 2),
            ("1.2300e-2", 123, 4, 6), ("-0.000", 0, 0, 3),
            ("100000000000000000000000000000000000000000000000", 1, -47, 0),
        ]
        for (text, coefficient, scale, display) in fixtures {
            #expect(try binary(text).root == .number(QueryNumericValue(value: ExactDecimal(coefficient: coefficient, scale: scale), displayScale: display)))
        }
    }

    @Test("Numeric coefficient and exponent bounds fail without expanding exponent zeros")
    func numericBoundaries() throws {
        #expect(try binary("99999999999999999999999999999999999999").root != .null)
        #expect(try binary("1e-16383").root != .null)
        for text in ["999999999999999999999999999999999999999", "1e-16384", "1e2147483649", "1e999999999999999999999999"] {
            #expect(throws: QueryValueError.self) { try binary(text) }
        }
    }

    @Test("Node construction rejects duplicate keys, invalid order and NUL")
    func malformedCanonicalNode() {
        let invalidMembers: [[QueryJSONBMember]] = [
            [QueryJSONBMember(key: "b", value: .null), QueryJSONBMember(key: "a", value: .null)],
            [QueryJSONBMember(key: "a", value: .null), QueryJSONBMember(key: "a", value: .null)],
            [QueryJSONBMember(key: "\u{0}", value: .null)],
        ]
        for members in invalidMembers {
            #expect(throws: QueryValueError.nonCanonicalJSONB) {
                try QueryJSONBNode.object(members, limits: limits())
            }
        }
        #expect(throws: QueryValueError.nonCanonicalJSONB) {
            try QueryJSONBValue(root: .string("\u{0}"), limits: limits())
        }
    }

    @Test("Lexical construction enforces exact and one-past node, depth and element budgets")
    func lexicalStructuralLimits() throws {
        let bytes = ByteString(utf8: "[null,[true]]")
        let json = try QueryJSONValue(bytes: bytes, limits: limits(nodes: 4, depth: 3, elements: 3))
        #expect(try json.measure().maximumNestingDepth == 3)
        #expect(throws: QueryValueError.self) { try QueryJSONValue(bytes: bytes, limits: limits(nodes: 3, depth: 3, elements: 3)) }
        #expect(throws: QueryValueError.self) { try QueryJSONValue(bytes: bytes, limits: limits(nodes: 4, depth: 2, elements: 3)) }
        #expect(throws: QueryValueError.self) { try QueryJSONValue(bytes: bytes, limits: limits(nodes: 4, depth: 3, elements: 2)) }
    }

    @Test("Lexical byte budget counts the retained owner instead of the visible slice")
    func retainedOwnerLimits() throws {
        let owner = ByteString(utf8: "null" + String(repeating: " ", count: 64))
        let slice = owner[0..<4]
        let retained = UInt64(try #require(slice.retainedByteCount))
        #expect(try QueryJSONValue(bytes: slice, limits: limits(bytes: retained)).measure().retainedByteCount == retained)
        #expect(throws: QueryValueError.self) { try QueryJSONValue(bytes: slice, limits: limits(bytes: retained - 1)) }
    }

    @Test("JSONB node byte and structural budgets enforce exact and one-past boundaries")
    func nodeLimits() throws {
        let array = try QueryJSONBNode.array([.string("😀")], limits: limits())
        let root = try QueryJSONBNode.object([QueryJSONBMember(key: "é", value: array)], limits: limits())
        let storage = root.storageFootprint
        #expect(storage.utf8ByteCount == 6)
        let retained = storage.retainedStorageByteCount + storage.utf8ByteCount
        let value = try QueryJSONBValue(root: root, limits: limits(bytes: retained, nodes: 3, depth: 3, elements: 2))
        #expect(try value.measure().retainedByteCount == retained)
        #expect(throws: QueryValueError.resourceLimit(resource: "retainedBytes", actual: retained, maximum: retained - 1)) {
            try QueryJSONBValue(root: root, limits: limits(bytes: retained - 1))
        }
        #expect(throws: QueryValueError.self) { try QueryJSONBValue(root: root, limits: limits(nodes: 2)) }
        #expect(throws: QueryValueError.self) { try QueryJSONBValue(root: root, limits: limits(depth: 2)) }
        #expect(throws: QueryValueError.self) { try QueryJSONBValue(root: root, limits: limits(elements: 1)) }
    }

    @Test("Unknown retained ownership fails instead of using visible byte count")
    func unknownRetainedOwnership() {
        let bytes = ByteString(retaining: UnknownByteOwner(bytes: [110, 117, 108, 108]))
        #expect(throws: QueryValueError.unknownRetainedByteCount) {
            try QueryJSONValue(bytes: bytes, limits: limits())
        }
    }

    private struct UnknownByteOwner: ByteStringOwner {
        let bytes: [UInt8]
        var count: Int { bytes.count }

        func borrowBytes(_ body: (UnsafeRawBufferPointer) throws -> Void) rethrows {
            try bytes.withUnsafeBytes(body)
        }
    }

    @Test("Composite copying rejects shallow depth and node budgets before descending a deep input")
    func copyTraversalAdmission() throws {
        let nesting = 4095
        let bytes = ByteString(utf8: String(repeating: "[", count: nesting) + "null" + String(repeating: "]", count: nesting))
        let sourceLimits = limits(bytes: 1_000_000, nodes: 4096, depth: 4096, elements: 4095)
        let json = try QueryJSONValue(bytes: bytes, limits: sourceLimits)
        let value = try QueryJSONBValue(json: json, limits: sourceLimits)
        let shallow = limits(bytes: 1_000_000, nodes: 4097, depth: 2, elements: 4096)
        #expect(throws: QueryValueError.resourceLimit(resource: "depth", actual: 3, maximum: 2)) {
            try QueryJSONBNode.array([value.root], limits: shallow)
        }
        #expect(throws: QueryValueError.resourceLimit(resource: "depth", actual: 3, maximum: 2)) {
            try QueryJSONBNode.object([QueryJSONBMember(key: "a", value: value.root)], limits: shallow)
        }
        #expect(throws: QueryValueError.resourceLimit(resource: "nodes", actual: 3, maximum: 2)) {
            try QueryJSONBNode.array([value.root], limits: limits(bytes: 1_000_000, nodes: 2, depth: 4097, elements: 4096))
        }
    }

    @Test("Depth 4096 supports parsing, equality, hashing, retained views and complete destruction")
    func iterativeDepth() throws {
        let nesting = 4095
        let bytes = ByteString(utf8: String(repeating: "[", count: nesting) + "null" + String(repeating: "]", count: nesting))
        let admitted = limits(bytes: 1_000_000, nodes: 4096, depth: 4096, elements: 4095)
        let json = try QueryJSONValue(bytes: bytes, limits: admitted)
        #expect(try json.measure().maximumNestingDepth == 4096)
        #expect(throws: QueryValueError.self) {
            try QueryJSONValue(bytes: bytes, limits: limits(nodes: 4096, depth: 4095, elements: 4095))
        }
        func exerciseAndRelease() throws(QueryValueError) -> QueryJSONBNode {
            let first = try QueryJSONBValue(json: json, limits: admitted)
            let second = try QueryJSONBValue(json: json, limits: admitted)
            #expect(first == second)
            #expect(first.hashValue == second.hashValue)
            #expect(Set([first, second]).count == 1)
            #expect(try first.measure().maximumNestingDepth == 4096)
            #expect(first.root.storageFootprint.nodeCapacity >= 4096)
            #expect(first.root.storageFootprint.retainedStorageByteCount > 0)
            guard case .array(let children) = first.root else { throw .nonCanonicalJSONB }
            return children[0]
        }
        do {
            let retainedChild = try exerciseAndRelease()
            let storage = retainedChild.storageFootprint
            let retained = storage.retainedStorageByteCount + storage.utf8ByteCount
            let exact = limits(bytes: retained, nodes: 4096, depth: 4096, elements: 4095)
            let retainedValue = try QueryJSONBValue(root: retainedChild, limits: exact)
            #expect(try retainedValue.measure().nodeCount == 4095)
            #expect(try retainedValue.measure().maximumNestingDepth == 4095)
            #expect(try retainedValue.measure().retainedByteCount == retained)
            #expect(throws: QueryValueError.resourceLimit(resource: "retainedBytes", actual: retained, maximum: retained - 1)) {
                try QueryJSONBValue(root: retainedChild, limits: limits(bytes: retained - 1, nodes: 4096, depth: 4096, elements: 4095))
            }
        }
        // The scope has released the final flat owner at full depth.
    }
}
