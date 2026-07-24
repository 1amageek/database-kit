import DatabaseTypes
import Testing
@testable import DatabaseKit

@Suite("Aggregation index kind validation")
struct AggregationIndexKindValidationTests {
    @Test("global descriptors preserve the zero-group canonical contract")
    func globalDescriptorsPreserveCanonicalContract() throws {
        let specifications: [(String, AggregationIndexMetadata.Operation)] = [
            ("global_count", .count),
            ("global_sum", .sum),
            ("global_average", .average),
            ("global_min", .minimum),
            ("global_max", .maximum),
        ]

        for (name, operation) in specifications {
            let descriptor = try Self.descriptor(named: name)
            let metadata = try AggregationIndexMetadata(canonical: descriptor.kind)

            #expect(metadata.operation == operation)
            #expect(metadata.groupByFieldNames.isEmpty)
            if operation == .count {
                #expect(descriptor.fieldNames.isEmpty)
                #expect(metadata.valueFieldName == nil)
                #expect(metadata.valueType == nil)
            } else {
                #expect(descriptor.fieldNames == ["value"])
                #expect(metadata.valueFieldName == "value")
                #expect(metadata.valueType == .int64)
            }
        }
    }

    @Test("grouped descriptors preserve group and value field roles")
    func groupedDescriptorsPreserveFieldRoles() throws {
        let specifications: [(String, AggregationIndexMetadata.Operation)] = [
            ("grouped_count", .count),
            ("grouped_sum", .sum),
            ("grouped_average", .average),
            ("grouped_min", .minimum),
            ("grouped_max", .maximum),
        ]

        for (name, operation) in specifications {
            let descriptor = try Self.descriptor(named: name)
            let metadata = try AggregationIndexMetadata(canonical: descriptor.kind)

            #expect(metadata.operation == operation)
            #expect(metadata.groupByFieldNames == ["group"])
            if operation == .count {
                #expect(descriptor.fieldNames == ["group"])
                #expect(metadata.valueFieldName == nil)
            } else {
                #expect(descriptor.fieldNames == ["group", "value"])
                #expect(metadata.valueFieldName == "value")
                #expect(metadata.valueType == .int64)
            }
        }
    }

    @Test("global and grouped field type validation succeeds")
    func validGlobalAndGroupedTypesSucceed() throws {
        #expect(
            CountIndexKind<AggregationKindValidationRecord>(groupBy: []).indexName
                == "AggregationKindValidationRecord_count"
        )
        try CountIndexKind<AggregationKindValidationRecord>.validateTypes([])
        try CountIndexKind<AggregationKindValidationRecord>.validateTypes([String.self])

        try SumIndexKind<AggregationKindValidationRecord, Int64>.validateTypes([Int64.self])
        try SumIndexKind<AggregationKindValidationRecord, Int64>.validateTypes(
            [String.self, Int64.self]
        )

        try AverageIndexKind<AggregationKindValidationRecord, Int64>.validateTypes([Int64.self])
        try AverageIndexKind<AggregationKindValidationRecord, Int64>.validateTypes(
            [String.self, Int64.self]
        )

        try MinIndexKind<AggregationKindValidationRecord, Int64>.validateTypes([Int64.self])
        try MinIndexKind<AggregationKindValidationRecord, Int64>.validateTypes(
            [String.self, Int64.self]
        )

        try MaxIndexKind<AggregationKindValidationRecord, Int64>.validateTypes([Int64.self])
        try MaxIndexKind<AggregationKindValidationRecord, Int64>.validateTypes(
            [String.self, Int64.self]
        )
    }

    @Test("value-bearing aggregation kinds reject zero fields with typed errors")
    func valueBearingKindsRejectZeroFields() {
        Self.expectInvalidTypeCount(index: "sum", expected: 1) {
            try SumIndexKind<AggregationKindValidationRecord, Int64>.validateTypes([])
        }
        Self.expectInvalidTypeCount(index: "average", expected: 1) {
            try AverageIndexKind<AggregationKindValidationRecord, Int64>.validateTypes([])
        }
        Self.expectInvalidTypeCount(index: "min", expected: 1) {
            try MinIndexKind<AggregationKindValidationRecord, Int64>.validateTypes([])
        }
        Self.expectInvalidTypeCount(index: "max", expected: 1) {
            try MaxIndexKind<AggregationKindValidationRecord, Int64>.validateTypes([])
        }
    }

    @Test("incompatible group and value types fail explicitly")
    func incompatibleTypesFailExplicitly() {
        Self.expectUnsupportedType(index: "count", type: NonComparableAggregationField.self) {
            try CountIndexKind<AggregationKindValidationRecord>.validateTypes(
                [NonComparableAggregationField.self]
            )
        }
        Self.expectUnsupportedType(index: "sum", type: String.self) {
            try SumIndexKind<AggregationKindValidationRecord, Int64>.validateTypes([String.self])
        }
        Self.expectUnsupportedType(index: "average", type: NonComparableAggregationField.self) {
            try AverageIndexKind<AggregationKindValidationRecord, Int64>.validateTypes(
                [NonComparableAggregationField.self, Int64.self]
            )
        }
        Self.expectUnsupportedType(index: "min", type: NonComparableAggregationField.self) {
            try MinIndexKind<AggregationKindValidationRecord, Int64>.validateTypes(
                [NonComparableAggregationField.self]
            )
        }
        Self.expectUnsupportedType(index: "max", type: NonComparableAggregationField.self) {
            try MaxIndexKind<AggregationKindValidationRecord, Int64>.validateTypes(
                [NonComparableAggregationField.self]
            )
        }
    }

    private static func descriptor(named name: String) throws -> IndexDescriptor {
        try #require(
            try AggregationKindValidationRecord.indexDescriptors.first {
                $0.name == name
            }
        )
    }

    private static func expectInvalidTypeCount(
        index: String,
        expected: Int,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            Issue.record("Expected invalidTypeCount for \(index)")
        } catch let error as IndexTypeValidationError {
            guard case .invalidTypeCount(
                let actualIndex,
                let actualExpected,
                let actual
            ) = error else {
                Issue.record("Expected invalidTypeCount for \(index), got \(error)")
                return
            }
            #expect(actualIndex == index)
            #expect(actualExpected == expected)
            #expect(actual == 0)
        } catch {
            Issue.record("Expected IndexTypeValidationError for \(index), got \(error)")
        }
    }

    private static func expectUnsupportedType(
        index: String,
        type expectedType: Any.Type,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            Issue.record("Expected unsupportedType for \(index)")
        } catch let error as IndexTypeValidationError {
            guard case .unsupportedType(let actualIndex, let actualType, _) = error else {
                Issue.record("Expected unsupportedType for \(index), got \(error)")
                return
            }
            #expect(actualIndex == index)
            #expect(ObjectIdentifier(actualType) == ObjectIdentifier(expectedType))
        } catch {
            Issue.record("Expected IndexTypeValidationError for \(index), got \(error)")
        }
    }
}

private struct NonComparableAggregationField {}

@Persistable
private struct AggregationKindValidationRecord {
    var id: String = "fixture-id"
    #Index(
        CountIndexKind<AggregationKindValidationRecord>(groupBy: []),
        name: "global_count"
    )
    #Index(
        SumIndexKind<AggregationKindValidationRecord, Int64>(groupBy: [], value: \.value),
        name: "global_sum"
    )
    #Index(
        AverageIndexKind<AggregationKindValidationRecord, Int64>(groupBy: [], value: \.value),
        name: "global_average"
    )
    #Index(
        MinIndexKind<AggregationKindValidationRecord, Int64>(groupBy: [], value: \.value),
        name: "global_min"
    )
    #Index(
        MaxIndexKind<AggregationKindValidationRecord, Int64>(groupBy: [], value: \.value),
        name: "global_max"
    )
    #Index(
        CountIndexKind<AggregationKindValidationRecord>(groupBy: [\.group]),
        name: "grouped_count"
    )
    #Index(
        SumIndexKind<AggregationKindValidationRecord, Int64>(groupBy: [\.group], value: \.value),
        name: "grouped_sum"
    )
    #Index(
        AverageIndexKind<AggregationKindValidationRecord, Int64>(groupBy: [\.group], value: \.value),
        name: "grouped_average"
    )
    #Index(
        MinIndexKind<AggregationKindValidationRecord, Int64>(groupBy: [\.group], value: \.value),
        name: "grouped_min"
    )
    #Index(
        MaxIndexKind<AggregationKindValidationRecord, Int64>(groupBy: [\.group], value: \.value),
        name: "grouped_max"
    )

    var group: String
    var value: Int64
}
