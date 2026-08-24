import DatabaseTypes
import Testing
@testable import DatabaseKit

@Persistable(type: "SchemaEvolutionUser")
struct SchemaEvolutionUserV1 {
    var id: String = "fixture-id"
    var name: String
    var email: String
}

@Persistable(type: "SchemaEvolutionUser")
struct SchemaEvolutionUserV2AppendOnly {
    var id: String = "fixture-id"
    var name: String
    var email: String
    var age: Int32 = 0
}

private func runtimeComputedAge() -> Int32 { 42 }

@Persistable
private enum SchemaEvolutionDefaultStatus: String {
    case active
    case inactive
}

@Persistable
private struct SchemaEvolutionEnumDefaultItem {
    var id: String = "fixture-id"
    var status: SchemaEvolutionDefaultStatus = .active
}

@Persistable(type: "SchemaEvolutionUser")
struct SchemaEvolutionUserV2RuntimeDefault {
    var id: String = "fixture-id"
    var name: String
    var email: String
    var age: Int32 = runtimeComputedAge()
}

@Persistable(type: "SchemaEvolutionUser")
struct SchemaEvolutionUserV2Reordered {
    var id: String = "fixture-id"
    var email: String
    var name: String
}

@Persistable(type: "SchemaEvolutionUser")
struct SchemaEvolutionUserV2Renamed {
    var id: String = "fixture-id"
    var fullName: String
    var email: String
}

enum SchemaEvolutionSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var entities: [Schema.Entity] {
        get throws(SchemaEntityError) {
            [try SchemaEvolutionUserV1.schemaEntity]
        }
    }
}

enum SchemaEvolutionSchemaV2AppendOnly: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var entities: [Schema.Entity] {
        get throws(SchemaEntityError) {
            [try SchemaEvolutionUserV2AppendOnly.schemaEntity]
        }
    }
}

enum SchemaEvolutionSchemaV2Reordered: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var entities: [Schema.Entity] {
        get throws(SchemaEntityError) {
            [try SchemaEvolutionUserV2Reordered.schemaEntity]
        }
    }
}

enum SchemaEvolutionSchemaV2RuntimeDefault: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var entities: [Schema.Entity] {
        get throws(SchemaEntityError) {
            [try SchemaEvolutionUserV2RuntimeDefault.schemaEntity]
        }
    }
}

enum SchemaEvolutionSchemaV2Renamed: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var entities: [Schema.Entity] {
        get throws(SchemaEntityError) {
            [try SchemaEvolutionUserV2Renamed.schemaEntity]
        }
    }
}

@Suite("Schema Evolution Tests")
struct SchemaEvolutionTests {
    @Test("Append-only field additions remain lightweight-compatible")
    func appendOnlyFieldAdditionIsCompatible() throws {
        let current = try SchemaEvolutionSchemaV2AppendOnly.makeSchema()
        let previous = try SchemaEvolutionSchemaV1.makeSchema()
        let report = current.compatibilityReport(from: previous)

        #expect(report.isLightweightCompatible)
        #expect(report.addedEntities.isEmpty)
        #expect(report.issues.isEmpty)
        #expect(report.entityReports.count == 1)
        #expect(report.entityReports[0].addedFields.map(\.name) == ["age"])
        #expect(report.entityReports[0].addedFields[0].defaultValue == .int32(0))
        #expect(report.entityReports[0].issues.isEmpty)
        #expect(try SchemaEvolutionSchemaV2AppendOnly.canLightweightMigrate(from: SchemaEvolutionSchemaV1.self))
    }

    @Test("Schema defaults use the declared Swift initializer")
    func runtimeComputedDefaultIsCanonicalized() throws {
        let current = try SchemaEvolutionSchemaV2RuntimeDefault.makeSchema()
        let previous = try SchemaEvolutionSchemaV1.makeSchema()
        let report = current.compatibilityReport(from: previous)

        #expect(report.isLightweightCompatible)
        #expect(report.allIssues.isEmpty)
        #expect(report.entityReports[0].addedFields[0].defaultValue == .int32(42))
    }

    @Test("Enum defaults use the declared Swift initializer")
    func enumDefaultIsCanonicalized() throws {
        let entity = try SchemaEvolutionEnumDefaultItem.schemaEntity

        #expect(
            entity.fieldMapByName["status"]?.defaultValue == .string("active")
        )
    }

    @Test("Append-only field additions decode missing fields using defaults")
    func appendOnlyFieldAdditionUsesDefaultsWhenDecodingSourceSchemaPayload() throws {
        let sourceRecord = SchemaEvolutionUserV1(name: "Alice", email: "alice@example.com")

        let fields = try PersistableFieldEncoder.encode(sourceRecord)
        let decoded = try SchemaEvolutionUserV2AppendOnly.decodePersistedFields(
            fields
        )

        #expect(decoded.id == sourceRecord.id)
        #expect(decoded.name == "Alice")
        #expect(decoded.email == "alice@example.com")
        #expect(decoded.age == 0)
    }

    @Test("Field reordering is rejected as incompatible")
    func fieldReorderingIsRejected() throws {
        let current = try SchemaEvolutionSchemaV2Reordered.makeSchema()
        let previous = try SchemaEvolutionSchemaV1.makeSchema()
        let report = current.compatibilityReport(from: previous)

        #expect(!report.isLightweightCompatible)
        #expect(
            report.allIssues.contains(
                .renumberedField(
                    entityName: "SchemaEvolutionUser",
                    fieldName: "email",
                    expected: 3,
                    actual: 2
                )
            )
        )
        #expect(
            report.allIssues.contains(
                .renumberedField(
                    entityName: "SchemaEvolutionUser",
                    fieldName: "name",
                    expected: 2,
                    actual: 3
                )
            )
        )
        #expect(try !SchemaEvolutionSchemaV2Reordered.canLightweightMigrate(from: SchemaEvolutionSchemaV1.self))
    }

    @Test("Field rename is rejected without explicit migration")
    func fieldRenameIsRejected() throws {
        let current = try SchemaEvolutionSchemaV2Renamed.makeSchema()
        let previous = try SchemaEvolutionSchemaV1.makeSchema()
        let report = current.compatibilityReport(from: previous)

        #expect(!report.isLightweightCompatible)
        #expect(
            report.allIssues.contains(
                .removedField(
                    entityName: "SchemaEvolutionUser",
                    fieldName: "name",
                    fieldNumber: 2
                )
            )
        )
        #expect(
            report.allIssues.contains(
                .nonAppendOnlyFieldAddition(
                    entityName: "SchemaEvolutionUser",
                    fieldName: "fullName",
                    fieldNumber: 2,
                    minimumAllowed: 4
                )
            )
        )
        #expect(try !SchemaEvolutionSchemaV2Renamed.canLightweightMigrate(from: SchemaEvolutionSchemaV1.self))
    }
}
