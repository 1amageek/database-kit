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

    @Test("value-bearing aggregation kinds reject zero fields with typed errors")
    func valueBearingKindsRejectZeroFields() {
        Self.expectInvalidFieldCount(index: "sum", expected: 1) {
            _ = try IndexDescriptor(
                name: "invalid_sum",
                definition: .sum,
                fields: [IndexField<AggregationKindValidationRecord>]()
            )
        }
        Self.expectInvalidFieldCount(index: "average", expected: 1) {
            _ = try IndexDescriptor(
                name: "invalid_average",
                definition: .average,
                fields: [IndexField<AggregationKindValidationRecord>]()
            )
        }
        Self.expectInvalidFieldCount(index: "min", expected: 1) {
            _ = try IndexDescriptor(
                name: "invalid_minimum",
                definition: .minimum,
                fields: [IndexField<AggregationKindValidationRecord>]()
            )
        }
        Self.expectInvalidFieldCount(index: "max", expected: 1) {
            _ = try IndexDescriptor(
                name: "invalid_maximum",
                definition: .maximum,
                fields: [IndexField<AggregationKindValidationRecord>]()
            )
        }
    }

    @Test("incompatible group and value fields fail explicitly")
    func incompatibleFieldsFailExplicitly() {
        Self.expectUnsupportedField(index: "count", fieldName: "unsupported") {
            _ = try IndexDescriptor(
                name: "invalid_count",
                definition: .count,
                fields: [
                    AggregationKindValidationRecord.fields.unsupported.ascending
                ]
            )
        }
        Self.expectUnsupportedField(index: "sum", fieldName: "group") {
            _ = try IndexDescriptor(
                name: "invalid_sum",
                definition: .sum,
                fields: [AggregationKindValidationRecord.fields.group.ascending]
            )
        }
        Self.expectUnsupportedField(index: "average", fieldName: "unsupported") {
            _ = try IndexDescriptor(
                name: "invalid_average",
                definition: .average,
                fields: [
                    AggregationKindValidationRecord.fields.unsupported.ascending,
                    AggregationKindValidationRecord.fields.value.ascending,
                ]
            )
        }
        Self.expectUnsupportedField(index: "min", fieldName: "unsupported") {
            _ = try IndexDescriptor(
                name: "invalid_minimum",
                definition: .minimum,
                fields: [
                    AggregationKindValidationRecord.fields.unsupported.ascending
                ]
            )
        }
        Self.expectUnsupportedField(index: "max", fieldName: "unsupported") {
            _ = try IndexDescriptor(
                name: "invalid_maximum",
                definition: .maximum,
                fields: [
                    AggregationKindValidationRecord.fields.unsupported.ascending
                ]
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
        } catch let declarationError as IndexDeclarationError {
            let error = declarationError.validationError
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
        fieldName expectedFieldName: String,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            Issue.record("Expected unsupportedField for \(index)")
        } catch let declarationError as IndexDeclarationError {
            let error = declarationError.validationError
            guard case .unsupportedField(let actualIndex, let actualField, _) = error else {
                Issue.record("Expected unsupportedField for \(index), got \(error)")
                return
            }
            #expect(actualIndex == index)
            #expect(actualField.name == expectedFieldName)
        } catch {
            Issue.record("Expected IndexValidationError for \(index), got \(error)")
        }
    }

}

@Persistable
private struct AggregationKindValidationRecord {
    var id: String = "fixture-id"
    #Index(
        .count,
        name: "global_count"
    )
    #Index(
        .sum,
        value: \AggregationKindValidationRecord.value,
        name: "global_sum"
    )
    #Index(
        .average,
        value: \AggregationKindValidationRecord.value,
        name: "global_average"
    )
    #Index(
        .minimum,
        value: \AggregationKindValidationRecord.value,
        name: "global_min"
    )
    #Index(
        .maximum,
        value: \AggregationKindValidationRecord.value,
        name: "global_max"
    )
    #Index(
        .count,
        groupBy: [\AggregationKindValidationRecord.group],
        name: "grouped_count"
    )
    #Index(
        .sum,
        groupBy: [\AggregationKindValidationRecord.group],
        value: \AggregationKindValidationRecord.value,
        name: "grouped_sum"
    )
    #Index(
        .average,
        groupBy: [\AggregationKindValidationRecord.group],
        value: \AggregationKindValidationRecord.value,
        name: "grouped_average"
    )
    #Index(
        .minimum,
        groupBy: [\AggregationKindValidationRecord.group],
        value: \AggregationKindValidationRecord.value,
        name: "grouped_min"
    )
    #Index(
        .maximum,
        groupBy: [\AggregationKindValidationRecord.group],
        value: \AggregationKindValidationRecord.value,
        name: "grouped_max"
    )

    var group: String
    var value: Int64
    var unsupported: FieldObject
}
