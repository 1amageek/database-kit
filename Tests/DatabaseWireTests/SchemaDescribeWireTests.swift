import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("Schema describe wire")
struct SchemaDescribeWireTests {
    @Test("Index types round-trip without string dispatch")
    func indexTypesRoundTrip() throws {
        let types: [IndexType] = [
            .ordered,
            .aggregate(.count),
            .aggregate(.percentile),
            .updateCount,
            .history,
            .bitmap,
            .leaderboard,
            .vector,
            .text(.fullText),
            .text(.autocomplete),
            .spatial,
            .rank,
            .graph(.property),
            .graph(.rdf),
            .graph(.ontologyProjection),
            .custom("third-party"),
        ]
        let response = SchemaDescribeOperation.Response(
            version: .init(1, 0, 0),
            entities: [
                SchemaDescribeOperation.Entity(
                    name: "IndexedEntity",
                    fields: [],
                    indexes: types.enumerated().map { offset, type in
                        SchemaDescribeOperation.Index(
                            name: "index_\(offset)",
                            type: type,
                            fields: [UInt32(offset + 1)]
                        )
                    }
                )
            ]
        )

        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperationCatalog.schemaDescribe,
            requestID: 71,
            response: response
        )
        let decoded = try DatabaseWireDecoder().decodeResponse(
            DatabaseOperationCatalog.schemaDescribe,
            from: frame,
            matching: 71
        )

        #expect(try decoded.get() == response)

        let invalidResponse = SchemaDescribeOperation.Response(
            version: .init(1, 0, 0),
            entities: [
                SchemaDescribeOperation.Entity(
                    name: "InvalidEntity",
                    fields: [],
                    indexes: [
                        SchemaDescribeOperation.Index(
                            name: "invalid_custom",
                            type: .custom(""),
                            fields: []
                        ),
                    ]
                ),
            ]
        )
        #expect(throws: DatabaseWireError.emptyCustomIndexIdentifier) {
            _ = try DatabaseWireEncoder().encodeResponse(
                DatabaseOperationCatalog.schemaDescribe,
                requestID: 72,
                response: invalidResponse
            )
        }

        var corrupted = Array(frame)
        let customIdentifier = Array("third-party".utf8)
        let identifierOffset = try #require(
            firstIndex(of: customIdentifier, in: corrupted)
        )
        #expect(corrupted[identifierOffset - 5] == 11)
        corrupted[identifierOffset - 5] = 0xFF
        #expect(throws: DatabaseWireError.invalidValueTag(0xFF)) {
            _ = try DatabaseWireDecoder().decodeResponse(
                DatabaseOperationCatalog.schemaDescribe,
                from: ByteString(corrupted),
                matching: 71
            )
        }
    }
}

private func firstIndex(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
    guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
    let lastStart = haystack.count - needle.count
    return (0...lastStart).first { offset in
        haystack[offset..<(offset + needle.count)].elementsEqual(needle)
    }
}
