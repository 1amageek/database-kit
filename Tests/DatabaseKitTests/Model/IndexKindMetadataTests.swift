import DatabaseKit
import DatabaseTypes
import Testing

@Suite("Index Kind Metadata")
struct IndexKindMetadataTests {
    @Test("Integer metadata accepts every exact FieldValue integer width")
    func integerMetadataPreservesExactIntegerSemantics() throws {
        let cases: [(FieldValue, Int)] = [
            (.int8(-8), -8),
            (.int16(-16), -16),
            (.int32(-32), -32),
            (.int64(-64), -64),
            (.uint8(8), 8),
            (.uint16(16), 16),
            (.uint32(32), 32),
            (.uint64(64), 64),
        ]

        for (value, expected) in cases {
            let metadata = makeMetadata(["value": value])
            #expect(try metadata.requireInt("value") == expected)
        }
    }

    @Test("Integer metadata rejects values outside the platform Int domain")
    func integerMetadataRejectsOverflow() {
        let metadata = makeMetadata(["value": .uint64(.max)])

        #expect(throws: IndexKindMetadataError.self) {
            try metadata.requireInt("value")
        }
    }

    @Test("Array metadata rejects a mixed element domain")
    func arrayMetadataRejectsMixedElements() {
        let metadata = makeMetadata([
            "values": .array([.string("first"), .int64(2)])
        ])

        #expect(throws: IndexKindMetadataError.self) {
            try metadata.requireStringArray("values")
        }
    }

    private func makeMetadata(
        _ values: [String: FieldValue]
    ) -> IndexKindMetadata {
        IndexKindMetadata(
            identifier: "test",
            subspaceStructure: .flat,
            fields: [
                IndexFieldMetadata(
                    identity: FieldIdentity(name: "value", number: 1)
                )
            ],
            metadata: values
        )
    }
}
