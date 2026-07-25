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

    @Test("global and grouped field validation succeeds")
    func validGlobalAndGroupedFieldsSucceed() throws {
        #expect(
            CountIndexKind<AggregationKindValidationRecord>(groupBy: []).indexName
                == "AggregationKindValidationRecord_count"
        )
        try CountIndexKind<AggregationKindValidationRecord>.validateFields([])
        try CountIndexKind<AggregationKindValidationRecord>.validateFields([
            Self.stringField
        ])

        try SumIndexKind<AggregationKindValidationRecord, Int64>.validateFields([
            Self.integerField
        ])
        try SumIndexKind<AggregationKindValidationRecord, Int64>.validateFields(
            [Self.stringField, Self.integerField]
        )

        try AverageIndexKind<AggregationKindValidationRecord, Int64>.validateFields([
            Self.integerField
        ])
        try AverageIndexKind<AggregationKindValidationRecord, Int64>.validateFields(
            [Self.stringField, Self.integerField]
        )

        try MinIndexKind<AggregationKindValidationRecord, Int64>.validateFields([
            Self.integerField
        ])
        try MinIndexKind<AggregationKindValidationRecord, Int64>.validateFields(
            [Self.stringField, Self.integerField]
        )

        try MaxIndexKind<AggregationKindValidationRecord, Int64>.validateFields([
            Self.integerField
        ])
        try MaxIndexKind<AggregationKindValidationRecord, Int64>.validateFields(
            [Self.stringField, Self.integerField]
        )
    }

    @Test("value-bearing aggregation kinds reject zero fields with typed errors")
    func valueBearingKindsRejectZeroFields() {
        Self.expectInvalidFieldCount(index: "sum", expected: 1) {
            try SumIndexKind<AggregationKindValidationRecord, Int64>.validateFields([])
        }
        Self.expectInvalidFieldCount(index: "average", expected: 1) {
            try AverageIndexKind<AggregationKindValidationRecord, Int64>.validateFields([])
        }
        Self.expectInvalidFieldCount(index: "min", expected: 1) {
            try MinIndexKind<AggregationKindValidationRecord, Int64>.validateFields([])
        }
        Self.expectInvalidFieldCount(index: "max", expected: 1) {
            try MaxIndexKind<AggregationKindValidationRecord, Int64>.validateFields([])
        }
    }

    @Test("incompatible group and value fields fail explicitly")
    func incompatibleFieldsFailExplicitly() {
        Self.expectUnsupportedField(index: "count", field: Self.objectField) {
            try CountIndexKind<AggregationKindValidationRecord>.validateFields(
                [Self.objectField]
            )
        }
        Self.expectUnsupportedField(index: "sum", field: Self.stringField) {
            try SumIndexKind<AggregationKindValidationRecord, Int64>.validateFields([
                Self.stringField
            ])
        }
        Self.expectUnsupportedField(index: "average", field: Self.objectField) {
            try AverageIndexKind<AggregationKindValidationRecord, Int64>.validateFields(
                [Self.objectField, Self.integerField]
            )
        }
        Self.expectUnsupportedField(index: "min", field: Self.objectField) {
            try MinIndexKind<AggregationKindValidationRecord, Int64>.validateFields(
                [Self.objectField]
            )
        }
        Self.expectUnsupportedField(index: "max", field: Self.objectField) {
            try MaxIndexKind<AggregationKindValidationRecord, Int64>.validateFields(
                [Self.objectField]
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

    private static func expectInvalidFieldCount(
        index: String,
        expected: Int,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            Issue.record("Expected invalidFieldCount for \(index)")
        } catch let error as IndexValidationError {
            guard case .invalidFieldCount(
                let actualIndex,
                let actualExpected,
                let actual
            ) = error else {
                Issue.record("Expected invalidFieldCount for \(index), got \(error)")
                return
            }
            #expect(actualIndex == index)
            #expect(actualExpected == expected)
            #expect(actual == 0)
        } catch {
            Issue.record("Expected IndexValidationError for \(index), got \(error)")
        }
    }

    private static func expectUnsupportedField(
        index: String,
        field expectedField: FieldSchema,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            Issue.record("Expected unsupportedField for \(index)")
        } catch let error as IndexValidationError {
            guard case .unsupportedField(let actualIndex, let actualField, _) = error else {
                Issue.record("Expected unsupportedField for \(index), got \(error)")
                return
            }
            #expect(actualIndex == index)
            #expect(actualField == expectedField)
        } catch {
            Issue.record("Expected IndexValidationError for \(index), got \(error)")
        }
    }

    private static let stringField = FieldSchema(
        name: "group",
        fieldNumber: 1,
        type: .string
    )
    private static let integerField = FieldSchema(
        name: "value",
        fieldNumber: 2,
        type: .int64
    )
    private static let objectField = FieldSchema(
        name: "unsupported",
        fieldNumber: 3,
        type: .object
    )
}

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
