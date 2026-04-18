import Testing
@testable import Core

@Persistable(type: "SchemaEvolutionUser")
struct SchemaEvolutionUserV1 {
    var name: String
    var email: String
}

@Persistable(type: "SchemaEvolutionUser")
struct SchemaEvolutionUserV2AppendOnly {
    var name: String
    var email: String
    var age: Int = 0
}

@Persistable(type: "SchemaEvolutionUser")
struct SchemaEvolutionUserV2Reordered {
    var email: String
    var name: String
}

@Persistable(type: "SchemaEvolutionUser")
struct SchemaEvolutionUserV2Renamed {
    var fullName: String
    var email: String
}

enum SchemaEvolutionSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static let models: [any Persistable.Type] = [SchemaEvolutionUserV1.self]
}

enum SchemaEvolutionSchemaV2AppendOnly: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static let models: [any Persistable.Type] = [SchemaEvolutionUserV2AppendOnly.self]
}

enum SchemaEvolutionSchemaV2Reordered: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static let models: [any Persistable.Type] = [SchemaEvolutionUserV2Reordered.self]
}

enum SchemaEvolutionSchemaV2Renamed: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static let models: [any Persistable.Type] = [SchemaEvolutionUserV2Renamed.self]
}

@Suite("Schema Evolution Tests")
struct SchemaEvolutionTests {
    @Test("Append-only field additions remain lightweight-compatible")
    func appendOnlyFieldAdditionIsCompatible() {
        let current = SchemaEvolutionSchemaV2AppendOnly.makeSchema()
        let previous = SchemaEvolutionSchemaV1.makeSchema()
        let report = current.compatibilityReport(from: previous)

        #expect(report.isLightweightCompatible)
        #expect(report.addedEntities.isEmpty)
        #expect(report.issues.isEmpty)
        #expect(report.entityReports.count == 1)
        #expect(report.entityReports[0].addedFields.map(\.name) == ["age"])
        #expect(report.entityReports[0].issues.isEmpty)
        #expect(SchemaEvolutionSchemaV2AppendOnly.canLightweightMigrate(from: SchemaEvolutionSchemaV1.self))
    }

    @Test("Append-only field additions decode missing fields using defaults")
    func appendOnlyFieldAdditionUsesDefaultsWhenDecodingLegacyPayload() throws {
        let encoder = ProtobufEncoder()
        let decoder = ProtobufDecoder()
        let legacy = SchemaEvolutionUserV1(name: "Alice", email: "alice@example.com")

        let data = try encoder.encode(legacy)
        let decoded = try decoder.decode(SchemaEvolutionUserV2AppendOnly.self, from: data)

        #expect(decoded.id == legacy.id)
        #expect(decoded.name == "Alice")
        #expect(decoded.email == "alice@example.com")
        #expect(decoded.age == 0)
    }

    @Test("Field reordering is rejected as incompatible")
    func fieldReorderingIsRejected() {
        let current = SchemaEvolutionSchemaV2Reordered.makeSchema()
        let previous = SchemaEvolutionSchemaV1.makeSchema()
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
        #expect(!SchemaEvolutionSchemaV2Reordered.canLightweightMigrate(from: SchemaEvolutionSchemaV1.self))
    }

    @Test("Field rename is rejected without explicit migration")
    func fieldRenameIsRejected() {
        let current = SchemaEvolutionSchemaV2Renamed.makeSchema()
        let previous = SchemaEvolutionSchemaV1.makeSchema()
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
        #expect(!SchemaEvolutionSchemaV2Renamed.canLightweightMigrate(from: SchemaEvolutionSchemaV1.self))
    }
}
