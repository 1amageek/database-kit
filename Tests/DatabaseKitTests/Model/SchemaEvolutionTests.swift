import DatabaseTypes
import Synchronization
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

private enum SchemaDefaultEvaluationCounter {
    private static let count = Mutex(0)

    static func next() -> Int32 {
        count.withLock { value in
            value += 1
            return Int32(value)
        }
    }

    static var value: Int {
        count.withLock { $0 }
    }
}

@Persistable
private struct SchemaEvolutionCachedDefaultItem {
    var id: String
    var value: Int32 = SchemaDefaultEvaluationCounter.next()
}

@Persistable
private struct SchemaEvolutionOptionalDefaultItem {
    var id: String
    var nickname: String? = "guest"
}

@Persistable
private struct SchemaEvolutionIndexedDefaultItem {
    #Index(.ordered(
        name: "schema_evolution_by_score",
        keys: [.ascending(\SchemaEvolutionIndexedDefaultItem.score)]
    ))

    var id: String
    var score: Int32 = 0
}

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
    @Test("Executable Swift initializers do not become schema defaults")
    func executableInitializersRemainConstructionPolicy() throws {
        let initialEvaluationCount = SchemaDefaultEvaluationCounter.value
        let first = try SchemaEvolutionCachedDefaultItem.schemaEntity
        let second = try SchemaEvolutionCachedDefaultItem.schemaEntity

        #expect(first == second)
        #expect(first.fieldMapByName["value"]?.defaultValue == nil)
        #expect(
            SchemaDefaultEvaluationCounter.value == initialEvaluationCount
        )
        #expect {
            _ = try SchemaEvolutionCachedDefaultItem.decodePersistedFields([
                try PersistableField(
                    number: 1,
                    name: "id",
                    value: .string("stored")
                ),
            ])
        } throws: { error in
            guard let decodingError = error as? PersistableDecodingError,
                  case .missingRequiredField("value") = decodingError else {
                return false
            }
            return true
        }
        #expect(
            SchemaDefaultEvaluationCounter.value == initialEvaluationCount
        )

        let item = SchemaEvolutionCachedDefaultItem(id: "constructed")
        #expect(item.value == Int32(initialEvaluationCount + 1))
        #expect(
            SchemaDefaultEvaluationCounter.value
                == initialEvaluationCount + 1
        )
    }

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

    @Test("Runtime-computed defaults require an explicit migration")
    func runtimeComputedDefaultIsNotPersistedInSchema() throws {
        let current = try SchemaEvolutionSchemaV2RuntimeDefault.makeSchema()
        let previous = try SchemaEvolutionSchemaV1.makeSchema()
        let report = current.compatibilityReport(from: previous)

        #expect(!report.isLightweightCompatible)
        #expect(report.entityReports[0].addedFields[0].defaultValue == nil)
        #expect(
            report.allIssues.contains(
                .addedFieldWithoutDefault(
                    entityName: "SchemaEvolutionUser",
                    fieldName: "age"
                )
            )
        )
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

    @Test("A stored null is distinct from a missing optional field")
    func explicitNullDoesNotUseTheSchemaDefault() throws {
        let id = SchemaEvolutionOptionalDefaultItem.fields.id.identity
        let nickname = SchemaEvolutionOptionalDefaultItem.fields.nickname.identity
        let missing = try SchemaEvolutionOptionalDefaultItem.decodePersistedFields([
            try PersistableField(
                number: try #require(UInt32(exactly: id.number)),
                name: id.name,
                value: .string("missing")
            ),
        ])
        let explicitNull = try SchemaEvolutionOptionalDefaultItem.decodePersistedFields([
            try PersistableField(
                number: try #require(UInt32(exactly: id.number)),
                name: id.name,
                value: .string("null")
            ),
            try PersistableField(
                number: try #require(UInt32(exactly: nickname.number)),
                name: nickname.name,
                value: .null
            ),
        ])

        #expect(missing.nickname == "guest")
        #expect(explicitNull.nickname == nil)
    }

    @Test("Compiled index projections retain canonical field defaults")
    func indexProjectionUsesCompleteFieldSchemas() throws {
        let entity = try SchemaEvolutionIndexedDefaultItem.schemaEntity
        let descriptor = try #require(entity.indexDescriptors.first)
        let projected = try #require(descriptor.fieldSchemas.first)
        let compiledDescriptors = try SchemaEvolutionIndexedDefaultItem
            .indexDescriptors

        #expect(projected.name == "score")
        #expect(projected.defaultValue == .int32(0))
        #expect(descriptor == compiledDescriptors.first)
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

@Suite("Directory Placement Evolution")
struct DirectoryPlacementEvolutionTests {
    private static let identifier = FieldSchema(
        name: "id",
        fieldNumber: 1,
        type: .string
    )

    private static let tenant = FieldSchema(
        name: "tenantID",
        fieldNumber: 2,
        type: .string
    )

    private static let region = FieldSchema(
        name: "region",
        fieldNumber: 3,
        type: .string
    )

    private static func entity(
        fields: [FieldSchema] = [tenant, region],
        components: [DirectoryPathComponent],
        layer: DirectoryLayer = .default,
        membership: PolymorphicMembership? = nil
    ) throws(SchemaEntityError) -> Schema.Entity {
        try Schema.Entity(
            name: "PlacedRecord",
            identifierType: .string,
            fields: [identifier] + fields,
            directoryComponents: components,
            directoryLayer: layer,
            polymorphicMembership: membership
        )
    }

    @Test("Unchanged placement reports no placement issue")
    func unchangedPlacementIsCompatible() throws {
        let components: [DirectoryPathComponent] = [
            .staticPath("tenants"),
            .dynamicField(fieldName: "tenantID"),
        ]
        let previous = try Self.entity(components: components, layer: .partition)
        let current = try Self.entity(components: components, layer: .partition)
        #expect(current.compatibilityReport(from: previous).isCompatible)
    }

    @Test("A changed static component value requires data movement")
    func changedStaticComponentValueIsReported() throws {
        let previous = try Self.entity(components: [.staticPath("tenants")])
        let current = try Self.entity(components: [.staticPath("accounts")])
        #expect(
            current.compatibilityReport(from: previous).issues == [
                .changedDirectoryComponents(
                    entityName: "PlacedRecord",
                    group: nil,
                    from: [.staticPath("tenants")],
                    to: [.staticPath("accounts")]
                )
            ]
        )
    }

    @Test("A reordered static component requires data movement")
    func reorderedStaticComponentIsReported() throws {
        let previous = try Self.entity(
            components: [.staticPath("tenants"), .staticPath("records")]
        )
        let current = try Self.entity(
            components: [.staticPath("records"), .staticPath("tenants")]
        )
        #expect(
            current.compatibilityReport(from: previous).issues == [
                .changedDirectoryComponents(
                    entityName: "PlacedRecord",
                    group: nil,
                    from: [.staticPath("tenants"), .staticPath("records")],
                    to: [.staticPath("records"), .staticPath("tenants")]
                )
            ]
        )
    }

    @Test("A changed dynamic field identity requires data movement")
    func changedDynamicFieldIdentityIsReported() throws {
        let previous = try Self.entity(
            components: [.dynamicField(fieldName: "tenantID")]
        )
        let current = try Self.entity(
            components: [.dynamicField(fieldName: "region")]
        )
        #expect(
            current.compatibilityReport(from: previous).issues == [
                .changedDirectoryComponents(
                    entityName: "PlacedRecord",
                    group: nil,
                    from: [.dynamicField(fieldName: "tenantID")],
                    to: [.dynamicField(fieldName: "region")]
                )
            ]
        )
    }

    @Test("A reordered dynamic component requires data movement")
    func reorderedDynamicComponentIsReported() throws {
        let previous = try Self.entity(
            components: [
                .dynamicField(fieldName: "tenantID"),
                .dynamicField(fieldName: "region"),
            ]
        )
        let current = try Self.entity(
            components: [
                .dynamicField(fieldName: "region"),
                .dynamicField(fieldName: "tenantID"),
            ]
        )
        let issues = current.compatibilityReport(from: previous).issues
        #expect(issues.count == 1)
        #expect(
            issues.first == .changedDirectoryComponents(
                entityName: "PlacedRecord",
                group: nil,
                from: [
                    .dynamicField(fieldName: "tenantID"),
                    .dynamicField(fieldName: "region"),
                ],
                to: [
                    .dynamicField(fieldName: "region"),
                    .dynamicField(fieldName: "tenantID"),
                ]
            )
        )
    }

    @Test("A changed leaf layer tag requires data movement")
    func changedLeafLayerTagIsReported() throws {
        let components: [DirectoryPathComponent] = [
            .staticPath("tenants"),
            .dynamicField(fieldName: "tenantID"),
        ]
        let previous = try Self.entity(components: components, layer: .default)
        let current = try Self.entity(components: components, layer: .partition)
        #expect(
            current.compatibilityReport(from: previous).issues == [
                .changedDirectoryLayer(
                    entityName: "PlacedRecord",
                    group: nil,
                    from: .default,
                    to: .partition
                )
            ]
        )
    }

    @Test("A changed dynamic component field kind is a field encoding change")
    func changedDynamicComponentFieldKindIsReported() throws {
        let components: [DirectoryPathComponent] = [
            .dynamicField(fieldName: "tenantID")
        ]
        let previousTenant = FieldSchema(
            name: "tenantID",
            fieldNumber: 2,
            type: .string
        )
        let currentTenant = FieldSchema(
            name: "tenantID",
            fieldNumber: 2,
            type: .uuid
        )
        let previous = try Self.entity(
            fields: [previousTenant],
            components: components
        )
        let current = try Self.entity(
            fields: [currentTenant],
            components: components
        )
        #expect(
            current.compatibilityReport(from: previous).issues == [
                .changedFieldEncoding(
                    entityName: "PlacedRecord",
                    fieldName: "tenantID",
                    from: previousTenant,
                    to: currentTenant
                )
            ]
        )
    }

    @Test("A changed polymorphic group requires data movement")
    func changedPolymorphicGroupIsReported() throws {
        let previous = try Self.entity(
            components: [],
            membership: PolymorphicMembership(
                identifier: "Shape",
                directoryComponents: [.staticPath("shapes")],
                directoryLayer: .default,
                indexes: []
            )
        )
        let current = try Self.entity(components: [])
        #expect(
            current.compatibilityReport(from: previous).issues == [
                .changedPolymorphicGroup(
                    entityName: "PlacedRecord",
                    from: "Shape",
                    to: nil
                )
            ]
        )
    }

    @Test("A changed shared polymorphic placement requires data movement")
    func changedPolymorphicPlacementIsReported() throws {
        let previous = try Self.entity(
            components: [],
            membership: PolymorphicMembership(
                identifier: "Shape",
                directoryComponents: [.staticPath("shapes")],
                directoryLayer: .default,
                indexes: []
            )
        )
        let current = try Self.entity(
            components: [],
            membership: PolymorphicMembership(
                identifier: "Shape",
                directoryComponents: [.staticPath("figures")],
                directoryLayer: .default,
                indexes: []
            )
        )
        #expect(
            current.compatibilityReport(from: previous).issues == [
                .changedDirectoryComponents(
                    entityName: "PlacedRecord",
                    group: "Shape",
                    from: [.staticPath("shapes")],
                    to: [.staticPath("figures")]
                )
            ]
        )
    }
}
