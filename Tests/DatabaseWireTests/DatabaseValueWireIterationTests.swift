import DatabaseValue
import DatabaseWire
import Testing

@Suite("Iterative DatabaseValue Wire")
struct DatabaseValueWireIterationTests {
    @Test("recursive value component preserves its canonical byte layout")
    func recursiveValueComponentPreservesCanonicalBytes() throws {
        let value = DatabaseValue.reference(
            PersistableIdentity(
                entity: "E",
                id: .composite([.string("id")]),
                partitions: [
                    DatabaseObjectField(
                        number: 7,
                        name: "p",
                        value: .object([
                            DatabaseObjectField(
                                number: 8,
                                name: "v",
                                value: .bool(true)
                            ),
                        ])
                    ),
                ]
            )
        )
        let expected: DatabaseBytes = [
            0x0C,
            0x01, 0x00, 0x00, 0x00, 0x45,
            0x06, 0x01, 0x00, 0x00, 0x00,
            0x03, 0x02, 0x00, 0x00, 0x00, 0x69, 0x64,
            0x01, 0x00, 0x00, 0x00,
            0x07, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x00, 0x00, 0x70,
            0x0B, 0x01, 0x00, 0x00, 0x00,
            0x08, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x00, 0x00, 0x76,
            0x01, 0x01,
        ]

        let encoded = try Self.encode(value)
        #expect(encoded == expected)

        var reader = DatabaseWireReader(encoded)
        let decoded = try DatabaseValue(from: &reader)
        try reader.ensureFullyRead()

        #expect(try Self.encode(decoded) == expected)
    }

    @Test("deep mixed value component encodes and decodes at the exact limits")
    func deepMixedValueComponentRoundTripsAtExactLimits() throws {
        let layerCount = DatabaseWireLimits.maximumSupportedNestingDepth - 1
        let valueDepth = layerCount + 1
        let referenceCount = layerCount / 3
        let objectCount = (layerCount * 2) + referenceCount + 1
        let encodedByteCount = (referenceCount * 40) + 1
        let limits = try DatabaseWireLimits(
            maximumFrameBytes: encodedByteCount,
            maximumStringBytes: 0,
            maximumByteStringBytes: 0,
            maximumCollectionCount: 1,
            maximumNestingDepth: valueDepth,
            maximumObjectCount: objectCount
        )
        let value = Self.makeDeepMixedValue(layerCount: layerCount)

        let encoded = try Self.encode(value, limits: limits)
        #expect(encoded.count == encodedByteCount)

        var reader = DatabaseWireReader(encoded, limits: limits)
        let decoded = try DatabaseValue(from: &reader)
        try reader.ensureFullyRead()

        let reencoded = try Self.encode(decoded, limits: limits)
        #expect(reencoded == encoded)

        let rejectedLimits = try DatabaseWireLimits(
            maximumFrameBytes: encodedByteCount,
            maximumStringBytes: 0,
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
            _ = try DatabaseValue(from: &rejectedReader)
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
        let value = DatabaseValue.array([.null, .null])
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
        let decoded = try DatabaseValue(from: &reader)
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
            _ = try DatabaseValue(from: &collectionReader)
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
            _ = try DatabaseValue(from: &objectReader)
        }
    }
}

private extension DatabaseValueWireIterationTests {
    static func encode(
        _ value: DatabaseValue,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> DatabaseBytes {
        try DatabaseWireWriter.encode(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
            try value.encode(into: &writer)
        }
    }

    static func makeDeepMixedValue(layerCount: Int) -> DatabaseValue {
        var value = DatabaseValue.null
        for index in 0..<layerCount {
            switch index % 3 {
            case 0:
                value = .array([value])
            case 1:
                value = .object([
                    DatabaseObjectField(
                        number: UInt32(index),
                        name: "",
                        value: value
                    ),
                ])
            default:
                value = .reference(
                    PersistableIdentity(
                        entity: "",
                        id: .string(""),
                        partitions: [
                            DatabaseObjectField(
                                number: 1,
                                name: "",
                                value: value
                            )
                        ]
                    )
                )
            }
        }
        return value
    }
}
