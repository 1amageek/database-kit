import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("Composite value Wire carriage")
struct S08CompositeWireTests {
    private let limits = DatabaseWireLimits.default.queryValueLimits

    @Test("Composite descriptor and value have exact tag26 and tag11 goldens")
    func zeroFieldGoldens() throws {
        let type = try QueryCompositeType(columns: [], limits: limits)
        let value = QueryValue.composite(try QueryCompositeValue(type: type, fields: [], limits: limits))
        #expect(try encodeType(.composite(type)) == ByteString([26, 0, 0, 0, 0]))
        #expect(try encode(value) == ByteString([11, 26, 0, 0, 0, 0, 0, 0, 0, 0]))
        try roundTrip(value, type: .sql(.composite(type)))
        try roundTrip(.primitive(.null), type: .sql(.composite(type)))
        let bytes = try encode(value)
        for (depth, objects, accepted) in [(2, 2, true), (1, 2, false), (2, 1, false)] {
            let bounded = try DatabaseWireLimits(maximumFrameBytes: 4_096, maximumStringBytes: 4_096,
                maximumByteStringBytes: 4_096, maximumCollectionCount: 0,
                maximumNestingDepth: depth, maximumObjectCount: objects)
            if accepted {
                let encoded = try DatabaseWireWriter.encode(limits: bounded) { writer throws(DatabaseWireError) in
                    try QueryValueWireCodec.encode(value, into: &writer)
                }
                #expect(encoded == bytes)
                var reader = DatabaseWireReader(bytes, limits: bounded)
                #expect(try QueryValueWireCodec.decode(from: &reader) == value)
                var validator = DatabaseWireReader(bytes, limits: bounded)
                try QueryValueWireCodec.validate(from: &validator)
            } else {
                #expect(throws: DatabaseWireError.self) {
                    try DatabaseWireWriter.encode(limits: bounded) { writer throws(DatabaseWireError) in
                        try QueryValueWireCodec.encode(value, into: &writer)
                    }
                }
                #expect(throws: DatabaseWireError.self) {
                    var reader = DatabaseWireReader(bytes, limits: bounded)
                    _ = try QueryValueWireCodec.decode(from: &reader)
                }
                #expect(throws: DatabaseWireError.self) {
                    var reader = DatabaseWireReader(bytes, limits: bounded)
                    try QueryValueWireCodec.validate(from: &reader)
                }
            }
        }

    }

    @Test("Duplicate names, selected primitive types and all-NULL non-NULL rows retain their descriptor")
    func descriptorAndNullIdentity() throws {
        let type = try descriptor()
        let value = QueryValue.composite(try QueryCompositeValue(type: type,
            fields: [.primitive(.null), .primitive(.null)], limits: limits))
        try roundTrip(value, type: .sql(.composite(type)))
        #expect(value != .primitive(.null))
        let typed = try encodeType(.composite(type))
        var reader = DatabaseWireReader(typed)
        #expect(try QueryIRDataTypeWireCodec.decode(from: &reader) == .composite(type))
        try reader.ensureFullyRead()
    }

    @Test("Nested composites and arrays retain lower bounds and positional fields")
    func nestedCollectionsRoundTrip() throws {
        let inner = try descriptor()
        let row = try QueryCompositeValue(type: inner,
            fields: [.primitive(.int32(7)), .primitive(.bytes([1, 2, 3]))], limits: limits)
        let array = try QueryArrayValue(elementType: .composite(inner),
            dimensions: [QueryArrayDimension(lowerBound: -3, length: 2)],
            elements: [.composite(row), .primitive(.null)], limits: limits)
        let outer = try QueryCompositeType(columns: [
            QueryColumn(number: 1, name: "rows", type: .sql(.array(.composite(inner))), isNullable: false),
            QueryColumn(number: 2, name: "row", type: .sql(.composite(inner)), isNullable: true),
        ], limits: limits)
        let value = QueryValue.composite(try QueryCompositeValue(type: outer,
            fields: [.array(array), .composite(row)], limits: limits))
        try roundTrip(value, type: .sql(.composite(outer)))
        let leafType = try QueryCompositeType(columns: [QueryColumn(number: 1, name: "f", type: .sql(.integer), isNullable: false)], limits: limits)
        let leafValue = try QueryCompositeValue(type: leafType, fields: [.primitive(.int32(1))], limits: limits)
        let rootType = try QueryCompositeType(columns: [QueryColumn(number: 1, name: "r", type: .sql(.composite(leafType)), isNullable: false)], limits: limits)
        let nested = QueryValue.composite(try QueryCompositeValue(type: rootType, fields: [.composite(leafValue)], limits: limits))
        let bytes = try encode(nested)
        for depth in [5, 6] {
            let bounded = try DatabaseWireLimits(maximumFrameBytes: 16_384, maximumStringBytes: 1_024,
                maximumByteStringBytes: 1_024, maximumCollectionCount: 32, maximumNestingDepth: depth, maximumObjectCount: 128)
            if depth == 5 {
                #expect(throws: DatabaseWireError.self) {
                    try DatabaseWireWriter.encode(limits: bounded) { writer throws(DatabaseWireError) in
                        try QueryValueWireCodec.encode(nested, into: &writer)
                    }
                }
                #expect(throws: DatabaseWireError.self) {
                    var reader = DatabaseWireReader(bytes, limits: bounded)
                    _ = try QueryValueWireCodec.decode(from: &reader)
                }
                #expect(throws: DatabaseWireError.self) {
                    var reader = DatabaseWireReader(bytes, limits: bounded)
                    try QueryValueWireCodec.validate(from: &reader)
                }
            } else {
                let restoredBytes = try DatabaseWireWriter.encode(limits: bounded) { writer throws(DatabaseWireError) in
                    try QueryValueWireCodec.encode(nested, into: &writer)
                }
                var reader = DatabaseWireReader(restoredBytes, limits: bounded)
                #expect(try QueryValueWireCodec.decode(from: &reader) == nested)
            }
        }

    }

    @Test("Malformed composite descriptor, ordinals, type, count and nullability fail typed")
    func malformedCompositeMetadata() throws {
        let integer = try QueryCompositeType(columns: [QueryColumn(number: 1, name: "f", type: .sql(.integer), isNullable: false)], limits: limits)
        let prefix = [UInt8(11)] + Array(try encodeType(.composite(integer)))
        let cases: [(ByteString, DatabaseWireError)] = [
            ([11, 2], .invalidQueryValue(.incompatibleType)),
            (ByteString(prefix + [0, 0, 0, 0]), .invalidQueryValue(.compositeFieldCountMismatch(expected: 1, actual: 0))),
            (ByteString(prefix + [1, 0, 0, 0, 0, 0]), .invalidQueryValue(.nullCompositeField(index: 0))),
            (ByteString(prefix + [1, 0, 0, 0, 0, 1, 1]), .invalidQueryValue(.elementTypeMismatch(index: 0))),
            ([11, 26, 1, 0, 0, 0, 0, 0, 0, 0], .invalidQueryValue(.invalidColumnNumber(0))),
        ]
        for (bytes, error) in cases {
            #expect(throws: error) { try decode(bytes) }
            #expect(throws: error) { try validate(bytes) }
        }
        var invalidBool = Array(try encodeType(.composite(integer)))
        invalidBool[invalidBool.count - 1] = 2
        #expect(throws: DatabaseWireError.invalidBool(2)) {
            var reader = DatabaseWireReader(ByteString(invalidBool))
            _ = try QueryIRDataTypeWireCodec.decode(from: &reader)
        }
    }

    @Test("External declarations reject changed names, order, type and nullability")
    func externalDescriptorMustMatch() throws {
        let original = try descriptor()
        let value = QueryValue.composite(try QueryCompositeValue(type: original,
            fields: [.primitive(.int32(1)), .primitive(.bytes([9]))], limits: limits))
        let bytes = try encode(value)
        let variants: [[QueryColumn]] = try [
            [QueryColumn(number: 1, name: "changed", type: .sql(.integer), isNullable: true), original.columns[1]],
            [QueryColumn(number: 1, name: "x", type: .sql(.bigint), isNullable: true), original.columns[1]],
            [QueryColumn(number: 1, name: "x", type: .sql(.integer), isNullable: false), original.columns[1]],
            [],
        ]
        for columns in variants {
            let type = try QueryCompositeType(columns: columns, limits: limits)
            #expect(throws: DatabaseWireError.invalidQueryValue(.incompatibleType)) { try validate(bytes, type: .sql(.composite(type))) }
        }
    }

    @Test("Every truncated descriptor/value prefix and trailing input fails at both decode boundaries")
    func everyPrefixFails() throws {
        let type = try descriptor()
        let value = QueryValue.composite(try QueryCompositeValue(type: type,
            fields: [.primitive(.int32(2)), .primitive(.bytes([7, 8]))], limits: limits))
        let bytes = try encode(value)
        for end in 0..<bytes.count {
            let prefix = bytes[0..<end]
            #expect(throws: DatabaseWireError.self) { try decode(prefix) }
            #expect(throws: DatabaseWireError.self) { try validate(prefix) }
        }
        let trailing = ByteString(Array(bytes) + [0])
        #expect(throws: DatabaseWireError.trailingBytes) { try decode(trailing) }
        #expect(throws: DatabaseWireError.trailingBytes) { try validate(trailing) }
        try roundTrip(value, type: .sql(.composite(type)))
    }

    @Test("Lazy result cells and retained views keep frame-backed byte leaves after release")
    func lazyCellsRetainOwners() throws {
        let type = try descriptor()
        let row = try QueryCompositeValue(type: type,
            fields: [.primitive(.int32(8)), .primitive(.bytes([1, 2, 3, 4]))], limits: limits)
        let columns = [try QueryColumn(number: 1, name: "x", type: .sql(.composite(type)), isNullable: true),
                       try QueryColumn(number: 2, name: "x", type: .sql(.composite(type)), isNullable: true)]
        var retained: QueryValue?
        do {
            let page = try makeTestQueryRowPage(columns: columns,
                rows: [QueryRow(values: [.composite(row), .primitive(.null)])], continuation: nil, snapshotVersion: 1)
            let frame = try DatabaseWireEncoder().encodeResponse(DatabaseOperationCatalog.queryExecute,
                requestID: 81, response: .rows(page))
            let response = try DatabaseWireDecoder().decodeResponse(DatabaseOperationCatalog.queryExecute, from: frame, matching: 81)
            guard case .success(.rows(let decoded)) = response else { Issue.record("Expected composite page"); return }
            #expect(decoded.retainedEncodedRows != nil)
            #expect(decoded.columns == columns)
            var iterator = decoded.makeRowIterator()
            let nextRow = try iterator.next()
            let materialized = try #require(nextRow)
            guard case .composite(let restored) = materialized.values[0] else { Issue.record("Expected composite cell"); return }
            retained = restored.fields[1]
            #expect(restored.type == type)
        }
        #expect(retained == .primitive(.bytes([1, 2, 3, 4])))
        retained = nil
    }

    @Test("Composite parameters, literals and zero-row declarations preserve selected types")
    func typedCarriageAndZeroRows() throws {
        let type = try descriptor()
        let value = QueryValue.composite(try QueryCompositeValue(type: type,
            fields: [.primitive(.int32(1)), .primitive(.null)], limits: limits))
        for parameter in [QueryParameter(position: 1, value: value, type: .sql(.composite(type))),
                          QueryParameter(position: 2, value: .primitive(.null), type: .sql(.composite(type)))] {
            let bytes = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in try parameter.encode(into: &writer) }
            var reader = DatabaseWireReader(bytes)
            #expect(try QueryParameter(from: &reader) == parameter)
            try reader.ensureFullyRead()
        }
        let literal = Literal.queryValue(value, type: .sql(.composite(type)))
        let bytes = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in try QueryIRLiteralWireCodec.encode(literal, into: &writer) }
        var reader = DatabaseWireReader(bytes)
        #expect(try QueryIRLiteralWireCodec.decode(from: &reader) == literal)
        try reader.ensureFullyRead()
        let columns = [try QueryColumn(number: 1, name: "x", type: .sql(.composite(type)), isNullable: true)]
        let page = try makeTestQueryRowPage(columns: columns, rows: [], continuation: nil, snapshotVersion: nil)
        let frame = try DatabaseWireEncoder().encodeResponse(DatabaseOperationCatalog.queryExecute, requestID: 82, response: .rows(page))
        let response = try DatabaseWireDecoder().decodeResponse(DatabaseOperationCatalog.queryExecute, from: frame, matching: 82)
        guard case .success(.rows(let decoded)) = response else { Issue.record("Expected zero-row page"); return }
        #expect(decoded.columns == columns && decoded.rowCount == 0)
    }

    @Test("Lazy composite arrays admit encoded bytes before materialized storage")
    func lazyMaterializationHasAnIndependentCapacityBoundary() throws {
        let type = try QueryCompositeType(columns: [], limits: limits)
        let empty = QueryValue.composite(try QueryCompositeValue(type: type, fields: [], limits: limits))
        let value = try QueryArrayValue(elementType: .composite(type),
            dimensions: [QueryArrayDimension(lowerBound: 1, length: 32)],
            elements: Array(repeating: empty, count: 32), limits: limits)
        let columns = [try QueryColumn(number: 1, name: "rows", type: .sql(.array(.composite(type))), isNullable: false)]
        let page = try makeTestQueryRowPage(columns: columns, rows: [QueryRow(values: [.array(value)])],
            continuation: nil, snapshotVersion: nil)
        let frame = try DatabaseWireEncoder().encodeResponse(DatabaseOperationCatalog.queryExecute, requestID: 83, response: .rows(page))
        let capacity = try #require(frame.retainedByteCount)
        let bounded = try DatabaseWireLimits(maximumFrameBytes: capacity, maximumStringBytes: capacity,
            maximumByteStringBytes: capacity, maximumCollectionCount: 128, maximumNestingDepth: 32, maximumObjectCount: 10_000)
        let response = try DatabaseWireDecoder(limits: bounded).decodeResponse(DatabaseOperationCatalog.queryExecute, from: frame, matching: 83)
        guard case .success(.rows(let decoded)) = response else { Issue.record("Expected lazy composite array page"); return }
        #expect(decoded.retainedEncodedRows != nil && decoded.rowCount == 1)
        var iterator = decoded.makeRowIterator()
        #expect(throws: DatabaseWireError.self) { try iterator.next() }
    }

    private func descriptor() throws -> QueryCompositeType {
        try QueryCompositeType(columns: [
            QueryColumn(number: 1, name: "x", type: .sql(.integer), isNullable: true),
            QueryColumn(number: 2, name: "x", type: .primitive(.bytes), isNullable: true),
        ], limits: limits)
    }

    private func encodeType(_ type: DataType) throws -> ByteString {
        try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in try QueryIRDataTypeWireCodec.encode(type, into: &writer) }
    }

    private func encode(_ value: QueryValue) throws -> ByteString {
        try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in try QueryValueWireCodec.encode(value, into: &writer) }
    }

    private func decode(_ bytes: ByteString) throws -> QueryValue {
        var reader = DatabaseWireReader(bytes)
        let result = try QueryValueWireCodec.decode(from: &reader)
        try reader.ensureFullyRead()
        return result
    }

    private func validate(_ bytes: ByteString, type: QueryColumnType? = nil) throws {
        var reader = DatabaseWireReader(bytes)
        try QueryValueWireCodec.validate(from: &reader, type: type)
        try reader.ensureFullyRead()
    }

    private func roundTrip(_ value: QueryValue, type: QueryColumnType) throws {
        let bytes = try encode(value)
        #expect(try decode(bytes) == value)
        try validate(bytes, type: type)
        #expect(try encode(decode(bytes)) == bytes)
    }
}
