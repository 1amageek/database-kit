import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("Query value wire grammar")
struct QueryValueWireCodecTests {
    private let limits = DatabaseWireLimits.default.queryValueLimits

    @Test func primitivePayloadRemainsUnchanged() throws {
        let primitive = FieldValue.object(try FieldObject([("a", .array([.null, .int64(7)]))]))
        let payload = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in
            try FieldValueWireCodec.encode(primitive, into: &writer)
        }
        let encoded = try encode(.primitive(primitive))
        #expect(encoded.first == 0)
        #expect(encoded.dropFirst().elementsEqual(payload))
        try roundTrip(.primitive(primitive), type: .primitive(.object))
    }

    @Test func numericPreservesDisplayScale() throws {
        let value = try QueryNumericValue(value: ExactDecimal(coefficient: 123, scale: 1), displayScale: 4)
        try roundTrip(.numeric(value), type: .sql(.decimal(precision: nil, scale: nil)))
    }

    @Test func lexicalJSONRetainsItsBytes() throws {
        let value = try QueryJSONValue(bytes: ByteString(Array(" { \"a\" : [null, 1.2300] } ".utf8)), limits: limits)
        try roundTrip(.json(value), type: .sql(.json))
    }

    @Test func jsonbPreservesCanonicalMembersAndExactNumbers() throws {
        let numeric = try QueryNumericValue(value: ExactDecimal(coefficient: 123, scale: 1), displayScale: 3)
        let root = try QueryJSONBNode.object([
            QueryJSONBMember(key: "z", value: .null),
            QueryJSONBMember(key: "aa", value: try .array([.bool(true), .string("é"), .number(numeric)], limits: limits)),
        ], limits: limits)
        let value = try QueryJSONBValue(root: root, limits: limits)
        try roundTrip(.jsonb(value), type: .sql(.jsonb))
    }

    @Test func arrayPreservesDimensionsLowerBoundsAndNulls() throws {
        let value = try QueryArrayValue(elementType: .integer,
            dimensions: [QueryArrayDimension(lowerBound: -2, length: 2), QueryArrayDimension(lowerBound: 7, length: 2)],
            elements: [.primitive(.int32(1)), .primitive(.null), .primitive(.int32(3)), .primitive(.int32(4))], limits: limits)
        try roundTrip(.array(value), type: .sql(.array(.integer)))
        let empty = try QueryArrayValue(elementType: .json, dimensions: [], elements: [], limits: limits)
        try roundTrip(.array(empty), type: .sql(.array(.json)))
    }

    @Test func intervalPreservesMixedSignsAndExtremeMicroseconds() throws {
        for microseconds in [Int64.min, -1, 0, 1, Int64.max] {
            let bytes = try raw { writer throws(DatabaseWireError) in
                writer.writeUInt8(5)
                writer.writeInt32(-3)
                writer.writeInt32(4)
                writer.writeInt64(microseconds)
            }
            var reader = DatabaseWireReader(bytes)
            let value = try QueryValueWireCodec.decode(from: &reader)
            guard case .interval(let interval) = value else { Issue.record("Expected interval"); return }
            #expect(interval.microseconds == microseconds)
            try roundTrip(value, type: .sql(.interval))
        }
    }

    @Test func malformedNumericIsRejectedWithoutRepair() throws {
        for (coefficient, scale, display) in [(Int128(120), Int32(2), Int32(2)), (0, 1, 0), (1, 1, 0)] {
            let bytes = try raw { writer throws(DatabaseWireError) in
                writer.writeUInt8(1)
                writer.writeInt128(coefficient)
                writer.writeInt32(scale)
                writer.writeInt32(display)
            }
            try reject(bytes)
        }
    }

    @Test func malformedJSONAndJSONBAreRejected() throws {
        try reject(try raw { writer throws(DatabaseWireError) in
            writer.writeUInt8(2)
            try writer.writeBytes(ByteString(Array("[1,]".utf8)))
        })
        for keys in [["aa", "z"], ["a", "a"], ["\0", "a"]] {
            try reject(try raw { writer throws(DatabaseWireError) in
                writer.writeUInt8(3)
                writer.writeUInt8(5)
                try writer.writeCount(keys.count)
                for key in keys { try writer.writeString(key); writer.writeUInt8(0) }
            })
        }
        try reject(try raw { writer throws(DatabaseWireError) in
            writer.writeUInt8(3); writer.writeUInt8(2); try writer.writeString("\0")
        })
    }

    @Test func invalidArrayShapeAndElementTypeAreRejected() throws {
        for (length, count, tag) in [(Int32(0), 0, UInt8(4)), (2, 1, 4), (1, 1, 13)] {
            try reject(try raw { writer throws(DatabaseWireError) in
                writer.writeUInt8(4)
                try QueryIRDataTypeWireCodec.encode(.integer, into: &writer)
                try writer.writeCount(1)
                writer.writeInt32(1)
                writer.writeInt32(length)
                try writer.writeCount(count)
                for _ in 0..<count {
                    writer.writeUInt8(0); writer.writeUInt8(tag)
                    if tag == 4 { writer.writeInt32(1) } else { try writer.writeString("bad") }
                }
            })
        }
    }

    @Test func declaredTypesAndNullabilityAreEnforced() throws {
        for (value, type, nullable) in [
            (QueryValue.primitive(.null), QueryColumnType.sql(.integer), false),
            (.primitive(.int64(1)), .sql(.integer), true),
            (.primitive(.float64(.infinity)), .sql(.doublePrecision), true),
        ] {
            var reader = DatabaseWireReader(try encode(value))
            #expect(throws: DatabaseWireError.invalidQueryValue(.incompatibleType)) {
                try QueryValueWireCodec.validate(from: &reader, type: type, isNullable: nullable)
            }
        }
        try roundTrip(.primitive(.array([.int32(1), .int32(2)])), type: .primitive(.int32, isArray: true))
        try roundTrip(.primitive(.array([.int32(1), .null])), type: .primitive(.int32, isArray: true))
    }

    @Test func unknownTruncatedAndTrailingInputFail() throws {
        try reject(ByteString([255]))
        try reject(ByteString([3, 255]))
        let value = QueryValue.numeric(try QueryNumericValue(value: ExactDecimal(coefficient: 5, scale: 1), displayScale: 1))
        let bytes = try encode(value)
        for count in 0..<bytes.count { try reject(ByteString(Array(bytes.prefix(count)))) }
        var trailing = Array(bytes)
        trailing.append(0)
        var reader = DatabaseWireReader(trailing)
        _ = try QueryValueWireCodec.decode(from: &reader)
        #expect(throws: DatabaseWireError.trailingBytes) { try reader.ensureFullyRead() }
    }

    @Test func deeplyNestedJSONBUsesBoundedFrames() throws {
        #expect(throws: DatabaseWireLimitsError.nestingDepthExceedsSupportedMaximum(actual: 4096, maximum: 1024)) {
            _ = try DatabaseWireLimits(maximumFrameBytes: 1_000_000, maximumStringBytes: 100_000,
                maximumByteStringBytes: 100_000, maximumCollectionCount: 10_000, maximumNestingDepth: 4096,
                maximumObjectCount: 10_000)
        }
        let deepLimits = try DatabaseWireLimits(maximumFrameBytes: 1_000_000, maximumStringBytes: 100_000,
            maximumByteStringBytes: 100_000, maximumCollectionCount: 10_000, maximumNestingDepth: 1024,
            maximumObjectCount: 10_000)
        let bytes = try raw { writer throws(DatabaseWireError) in
            writer.writeUInt8(3)
            for _ in 0..<1023 { writer.writeUInt8(4); try writer.writeCount(1) }
            writer.writeUInt8(0)
        }
        var validator = DatabaseWireReader(bytes, limits: deepLimits)
        try QueryValueWireCodec.validate(from: &validator, type: .sql(.jsonb))
        try validator.ensureFullyRead()
        var reader = DatabaseWireReader(bytes, limits: deepLimits)
        let value = try QueryValueWireCodec.decode(from: &reader)
        try reader.ensureFullyRead()
        guard case .jsonb(let jsonb) = value, case .array(let children) = jsonb.root else {
            Issue.record("Expected JSONB array"); return
        }
        let storage = jsonb.root.storageFootprint
        #expect(storage.nodeCapacity >= 1024)
        #expect(children[0].storageFootprint == storage)
        #expect(try jsonb.measure().retainedByteCount == storage.retainedStorageByteCount + storage.utf8ByteCount)
        let encoded = try DatabaseWireWriter.encode(limits: deepLimits) { writer throws(DatabaseWireError) in
            try QueryValueWireCodec.encode(value, into: &writer)
        }
        #expect(encoded == bytes)
        let tooDeep = try raw { writer throws(DatabaseWireError) in
            writer.writeUInt8(3)
            for _ in 0..<1024 { writer.writeUInt8(4); try writer.writeCount(1) }
            writer.writeUInt8(0)
        }
        var rejected = DatabaseWireReader(tooDeep, limits: deepLimits)
        #expect(throws: DatabaseWireError.nestingTooDeep(actual: 1025, maximum: 1024)) {
            try QueryValueWireCodec.validate(from: &rejected)
        }
    }

    private func encode(_ value: QueryValue) throws(DatabaseWireError) -> ByteString {
        try raw { writer throws(DatabaseWireError) in try QueryValueWireCodec.encode(value, into: &writer) }
    }

    private func raw(_ body: (inout DatabaseWireWriter) throws(DatabaseWireError) -> Void) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(body)
    }

    private func roundTrip(_ value: QueryValue, type: QueryColumnType) throws {
        let bytes = try encode(value)
        var reader = DatabaseWireReader(bytes)
        #expect(try QueryValueWireCodec.decode(from: &reader) == value)
        try reader.ensureFullyRead()
        var validator = DatabaseWireReader(bytes)
        try QueryValueWireCodec.validate(from: &validator, type: type)
        try validator.ensureFullyRead()
    }

    private func reject(_ bytes: ByteString) throws {
        var reader = DatabaseWireReader(bytes)
        #expect(throws: DatabaseWireError.self) { _ = try QueryValueWireCodec.decode(from: &reader) }
        var validator = DatabaseWireReader(bytes)
        #expect(throws: DatabaseWireError.self) { try QueryValueWireCodec.validate(from: &validator) }
    }
}
