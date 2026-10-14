import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("Query Wire root and materialization ledgers")
struct QueryWireRetentionLedgerTests {
    @Test("independent JSONB owners share one actual retention ledger across arrays and row cells")
    func cumulativeJSONBRetention() throws {
        let valueLimits = DatabaseWireLimits.default.queryValueLimits
        let root = try QueryJSONBNode.array(Array(repeating: .null, count: 1000), limits: valueLimits)
        let jsonb = try QueryJSONBValue(root: root, limits: valueLimits)
        let values: [QueryValue] = [.jsonb(jsonb), .jsonb(jsonb)]
        let array = try QueryArrayValue(elementType: .jsonb,
            dimensions: [QueryArrayDimension(lowerBound: 1, length: 2)], elements: values, limits: valueLimits)
        let encoded = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in
            try QueryValueWireCodec.encode(.array(array), into: &writer)
        }
        var calibration = DatabaseWireReader(encoded)
        let decoded = try QueryValueWireCodec.decode(from: &calibration)
        try calibration.ensureFullyRead()
        let retainedBytes = try QueryValueValidator.measure(decoded).retainedByteCount
        let retained = try #require(Int(exactly: retainedBytes))
        let exactLimits = try jsonbLimits(retained: retained)
        let onePastLimits = try jsonbLimits(retained: retained - 1)
        let expected = DatabaseWireError.invalidQueryValue(.resourceLimit(
            resource: "jsonbRetainedBytes", actual: retainedBytes, maximum: retainedBytes - 1))
        var exactArray = DatabaseWireReader(encoded, limits: exactLimits)
        #expect(try QueryValueWireCodec.decode(from: &exactArray) == decoded)
        try exactArray.ensureFullyRead()
        var onePastArray = DatabaseWireReader(encoded, limits: onePastLimits)
        #expect(throws: expected) { _ = try QueryValueWireCodec.decode(from: &onePastArray) }

        let wrapped = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in
            for value in values {
                try writer.writeLengthPrefixed { child throws(DatabaseWireError) in
                    try QueryValueWireCodec.encode(value, into: &child)
                }
            }
        }
        var exactChildren = DatabaseWireReader(wrapped, limits: exactLimits)
        for value in values {
            #expect(try exactChildren.readLengthPrefixed { child throws(DatabaseWireError) in
                try QueryValueWireCodec.decode(from: &child)
            } == value)
        }
        try exactChildren.ensureFullyRead()
        var onePastChildren = DatabaseWireReader(wrapped, limits: onePastLimits)
        _ = try onePastChildren.readLengthPrefixed { child throws(DatabaseWireError) in
            try QueryValueWireCodec.decode(from: &child)
        }
        #expect(throws: expected) {
            _ = try onePastChildren.readLengthPrefixed { child throws(DatabaseWireError) in
                try QueryValueWireCodec.decode(from: &child)
            }
        }

        let columns = [
            try QueryColumn(number: 1, name: "a", type: .sql(.jsonb), isNullable: false),
            try QueryColumn(number: 2, name: "b", type: .sql(.jsonb), isNullable: false),
        ]
        let row = QueryRow(values: values)
        let page = try makeTestQueryRowPage(columns: columns, rows: [row], snapshotVersion: 9)
        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperationCatalog.queryExecute, requestID: 20, response: .rows(page))
        for (limits, acceptsRow) in [(exactLimits, true), (onePastLimits, false)] {
            let response = try DatabaseWireDecoder(limits: limits).decodeResponse(
                DatabaseOperationCatalog.queryExecute, from: frame, matching: 20)
            guard case .success(.rows(let lazy)) = response else {
                Issue.record("Expected a lazy JSONB page"); return
            }
            #expect(lazy.retainedEncodedRows != nil)
            var iterator = lazy.makeRowIterator()
            if acceptsRow {
                #expect(try iterator.next() == row)
                #expect(try iterator.next() == nil)
            } else {
                #expect(throws: expected) { _ = try iterator.next() }
            }
        }
    }

    @Test("two JSON views retain one admitted root without raising the byte limit")
    func sharedRootArray() throws {
        let prefix = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in
            writer.writeUInt8(4)
            try QueryIRDataTypeWireCodec.encode(.json, into: &writer)
            try writer.writeCount(1)
            writer.writeInt32(-1)
            writer.writeInt32(2)
            try writer.writeCount(2)
            for _ in 0..<2 {
                writer.writeUInt8(2)
                try writer.writeBytes(ByteString(utf8: "null"))
            }
        }
        let capacity = 4 * 1_024 * 1_024
        let backing = ByteString.copying(count: capacity) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            prefix.withUnsafeBytes { source in
                destination.copyMemory(from: source)
            }
        }
        let frame = backing[0..<prefix.count]
        let retained = try #require(backing.retainedByteCount)
        let exactLimits = try limits(frame: retained)
        var reader = DatabaseWireReader(frame, limits: exactLimits)
        let value = try QueryValueWireCodec.decode(from: &reader)
        try reader.ensureFullyRead()
        guard case .array(let array) = value,
              case .json(let first) = array.elements[0],
              case .json(let second) = array.elements[1] else {
            Issue.record("Expected two lexical JSON values")
            return
        }
        #expect(first.bytes.retainedByteCount == backing.retainedByteCount)
        #expect(second.bytes.retainedByteCount == backing.retainedByteCount)
        #expect(try QueryValueValidator.measure(value).retainedByteCount
                == UInt64(retained) * 2)
        var validator = DatabaseWireReader(frame, limits: exactLimits)
        try QueryValueWireCodec.validate(from: &validator, type: .sql(.array(.json)))
        try validator.ensureFullyRead()
        var onePast = DatabaseWireReader(frame, limits: try limits(frame: retained - 1))
        #expect(throws: DatabaseWireError.invalidQueryValue(.resourceLimit(
            resource: "rootRetainedBytes", actual: UInt64(retained), maximum: UInt64(retained - 1)
        ))) {
            _ = try QueryValueWireCodec.decode(from: &onePast)
        }
    }

    @Test("visible frame size does not admit an oversized retained backing")
    func oversizedBacking() throws {
        let owner = ByteString(repeating: 0, count: 128)
        var reader = DatabaseWireReader(owner[0..<1], limits: try limits(frame: 64))
        #expect(throws: DatabaseWireError.self) { try reader.admitQueryRootRetention() }
    }

    @Test("unknown capacity requires an explicit owned copy")
    func unknownBacking() throws {
        let source = ByteString(retaining: UnknownOwner(bytes: [0, 0]))
        var reader = DatabaseWireReader(source)
        #expect(throws: DatabaseWireError.invalidQueryValue(.unknownRetainedByteCount)) {
            _ = try QueryValueWireCodec.decode(from: &reader)
        }
        var owned = DatabaseWireReader(ByteString(source.copyBytes()))
        #expect(try QueryValueWireCodec.decode(from: &owned) == .primitive(.null))
        try owned.ensureFullyRead()
    }

    @Test("child readers preserve the parent query representation ledger")
    func childLedger() throws {
        let frame = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in
            try writer.writeBytes(ByteString(utf8: "ab"))
        }
        var reader = DatabaseWireReader(frame, limits: try limits(frame: 16))
        try reader.beginQueryPayload()
        defer { reader.endQueryPayload() }
        try reader.registerQueryView(ByteString(repeating: 0, count: 14))
        #expect(throws: DatabaseWireError.invalidQueryValue(
            .resourceLimit(resource: "viewBytes", actual: 18, maximum: 16)
        )) {
            _ = try reader.readLengthPrefixed { child throws(DatabaseWireError) in
                try child.readUnframedBytes(count: 2)
            }
        }
    }

    @Test("JSONB strings honor exact and one-past string limits in validation and decoding")
    func jsonbStringBudget() throws {
        let frame = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in
            writer.writeUInt8(3)
            writer.writeUInt8(2)
            try writer.writeString("abc")
        }
        var exact = DatabaseWireReader(frame, limits: try limits(frame: 64, string: 3))
        try QueryValueWireCodec.validate(from: &exact, type: .sql(.jsonb))
        try exact.ensureFullyRead()
        var onePast = DatabaseWireReader(frame, limits: try limits(frame: 64, string: 2))
        #expect(throws: DatabaseWireError.stringTooLarge(actual: 3, maximum: 2)) {
            _ = try QueryValueWireCodec.decode(from: &onePast)
        }
    }

    private func limits(frame: Int, string: Int = 16) throws -> DatabaseWireLimits {
        try DatabaseWireLimits(maximumFrameBytes: frame, maximumStringBytes: string,
                               maximumByteStringBytes: frame, maximumCollectionCount: 64,
                               maximumNestingDepth: 16, maximumObjectCount: 256)
    }

    private func jsonbLimits(retained: Int) throws -> DatabaseWireLimits {
        try DatabaseWireLimits(maximumFrameBytes: retained, maximumStringBytes: retained,
                               maximumByteStringBytes: retained, maximumCollectionCount: 4096,
                               maximumNestingDepth: 16, maximumObjectCount: 10_000)
    }

    private struct UnknownOwner: ByteStringOwner {
        let bytes: [UInt8]
        var count: Int { bytes.count }
        func borrowBytes(_ body: (UnsafeRawBufferPointer) throws -> Void) rethrows {
            try bytes.withUnsafeBytes(body)
        }
    }
}
