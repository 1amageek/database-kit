import DatabaseTypes
@_spi(DatabaseServer) @testable import DatabaseWire
import Testing

@Suite("Iterative FieldValue Wire")
struct FieldValueWireIterationTests {
    @Test("recursive value component preserves its canonical byte layout")
    func recursiveValueComponentPreservesCanonicalBytes() throws {
        let value = FieldValue.reference(
            try EntityReference(
                entity: "E",
                id: .composite([.string("id")]),
                partitions: try FieldObject([
                    (
                        key: "p",
                        value: .object(
                            try FieldObject([
                                (key: "v", value: .bool(true)),
                            ])
                        )
                    ),
                ])
            )
        )
        let expected: ByteString = [
            0x1B,
            0x01, 0x00, 0x00, 0x00, 0x45,
            0x0C, 0x01, 0x00, 0x00, 0x00,
            0x09, 0x02, 0x00, 0x00, 0x00, 0x69, 0x64,
            0x01, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x00, 0x00, 0x70,
            0x1A, 0x01, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x00, 0x00, 0x76,
            0x01, 0x01,
        ]

        let encoded = try Self.encode(value)
        #expect(encoded == expected)

        var reader = DatabaseWireReader(encoded)
        let decoded = try FieldValue(from: &reader)
        try reader.ensureFullyRead()

        #expect(try Self.encode(decoded) == expected)
    }

    @Test("deep mixed value component encodes and decodes at the exact limits")
    func deepMixedValueComponentRoundTripsAtExactLimits() throws {
        let layerCount = DatabaseWireLimits.maximumSupportedNestingDepth - 1
        let valueDepth = layerCount + 1
        let referenceCount = layerCount / 3
        let objectCount = (layerCount * 2) + referenceCount + 1
        let encodedByteCount = (referenceCount * 33) + 1
        let limits = try DatabaseWireLimits(
            maximumFrameBytes: encodedByteCount,
            maximumStringBytes: 1,
            maximumByteStringBytes: 0,
            maximumCollectionCount: 1,
            maximumNestingDepth: valueDepth,
            maximumObjectCount: objectCount
        )
        let value = try Self.makeDeepMixedValue(layerCount: layerCount)

        let encoded = try Self.encode(value, limits: limits)
        #expect(encoded.count == encodedByteCount)

        var reader = DatabaseWireReader(encoded, limits: limits)
        let decoded = try FieldValue(from: &reader)
        try reader.ensureFullyRead()

        let reencoded = try Self.encode(decoded, limits: limits)
        #expect(reencoded == encoded)

        let rejectedLimits = try DatabaseWireLimits(
            maximumFrameBytes: encodedByteCount,
            maximumStringBytes: 1,
            maximumByteStringBytes: 0,
            maximumCollectionCount: 1,
            maximumNestingDepth: valueDepth - 1,
            maximumObjectCount: objectCount
        )
        #expect(
            throws: DatabaseWireError.nestingTooDeep(
                actual: valueDepth,
                maximum: valueDepth - 1
            )
        ) {
            _ = try Self.encode(value, limits: rejectedLimits)
        }

        var rejectedReader = DatabaseWireReader(
            encoded,
            limits: rejectedLimits
        )
        #expect(
            throws: DatabaseWireError.nestingTooDeep(
                actual: valueDepth,
                maximum: valueDepth - 1
            )
        ) {
            _ = try FieldValue(from: &rejectedReader)
        }

    }

    @Test("wire limits reject nesting depths that owned values cannot release safely")
    func unsafeNestingLimitIsRejected() {
        let unsupportedDepth = DatabaseWireLimits.maximumSupportedNestingDepth + 1

        #expect(
            throws: DatabaseWireLimitsError.nestingDepthExceedsSupportedMaximum(
                actual: unsupportedDepth,
                maximum: DatabaseWireLimits.maximumSupportedNestingDepth
            )
        ) {
            _ = try DatabaseWireLimits(
                maximumFrameBytes: 1,
                maximumStringBytes: 1,
                maximumByteStringBytes: 1,
                maximumCollectionCount: 1,
                maximumNestingDepth: unsupportedDepth,
                maximumObjectCount: 1
            )
        }
    }

    @Test("collection and object limits reject the exact first excess")
    func collectionAndObjectLimitsRejectExactFirstExcess() throws {
        let value = FieldValue.array([.null, .null])
        let acceptedLimits = try DatabaseWireLimits(
            maximumFrameBytes: 7,
            maximumStringBytes: 0,
            maximumByteStringBytes: 0,
            maximumCollectionCount: 2,
            maximumNestingDepth: 2,
            maximumObjectCount: 5
        )
        let encoded = try Self.encode(value, limits: acceptedLimits)
        var reader = DatabaseWireReader(encoded, limits: acceptedLimits)
        let decoded = try FieldValue(from: &reader)
        try reader.ensureFullyRead()
        #expect(try Self.encode(decoded, limits: acceptedLimits) == encoded)

        let collectionLimits = try DatabaseWireLimits(
            maximumFrameBytes: 7,
            maximumStringBytes: 0,
            maximumByteStringBytes: 0,
            maximumCollectionCount: 1,
            maximumNestingDepth: 2,
            maximumObjectCount: 5
        )
        #expect(
            throws: DatabaseWireError.collectionTooLarge(
                actual: 2,
                maximum: 1
            )
        ) {
            _ = try Self.encode(value, limits: collectionLimits)
        }
        var collectionReader = DatabaseWireReader(
            encoded,
            limits: collectionLimits
        )
        #expect(
            throws: DatabaseWireError.collectionTooLarge(
                actual: 2,
                maximum: 1
            )
        ) {
            _ = try FieldValue(from: &collectionReader)
        }

        let objectLimits = try DatabaseWireLimits(
            maximumFrameBytes: 7,
            maximumStringBytes: 0,
            maximumByteStringBytes: 0,
            maximumCollectionCount: 2,
            maximumNestingDepth: 2,
            maximumObjectCount: 4
        )
        #expect(
            throws: DatabaseWireError.objectBudgetExceeded(
                actual: 5,
                maximum: 4
            )
        ) {
            _ = try Self.encode(value, limits: objectLimits)
        }
        var objectReader = DatabaseWireReader(
            encoded,
            limits: objectLimits
        )
        #expect(
            throws: DatabaseWireError.objectBudgetExceeded(
                actual: 5,
                maximum: 4
            )
        ) {
            _ = try FieldValue(from: &objectReader)
        }
    }
}

private extension FieldValueWireIterationTests {
    static func encode(
        _ value: FieldValue,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
            try value.encode(into: &writer)
        }
    }

    static func makeDeepMixedValue(
        layerCount: Int
    ) throws -> FieldValue {
        var value = FieldValue.null
        for index in 0..<layerCount {
            switch index % 3 {
            case 0:
                value = .array([value])
            case 1:
                value = .object(
                    try FieldObject([
                        (key: "", value: value),
                    ])
                )
            default:
                value = .reference(
                    try EntityReference(
                        entity: "E",
                        id: .string(""),
                        partitions: try FieldObject([
                            (key: "", value: value),
                        ])
                    )
                )
            }
        }
        return value
    }
}
