import DatabaseTypes
import DatabaseValue
import Testing
@testable import Core

@Persistable
private struct SchemaValidationEntity {
    var first: String
    var second: String
}

@Suite("Schema Validation")
struct SchemaValidationTests {
    @Test("Duplicate entity names fail schema construction")
    func duplicateEntityNamesFailConstruction() {
        let entity = Schema.Entity(
            name: "DuplicateEntity",
            fields: []
        )

        #expect(throws: SchemaError.duplicateEntityName("DuplicateEntity")) {
            try Schema(entities: [entity, entity])
        }
    }

    @Test("Duplicate index names fail schema construction")
    func duplicateIndexNamesFailConstruction() {
        let first = IndexDescriptor(
            name: "duplicate_index",
            keyPaths: [\SchemaValidationEntity.first],
            kind: ScalarIndexKind<SchemaValidationEntity>(
                fields: [\SchemaValidationEntity.first]
            )
        )
        let second = IndexDescriptor(
            name: "duplicate_index",
            keyPaths: [\SchemaValidationEntity.second],
            kind: ScalarIndexKind<SchemaValidationEntity>(
                fields: [\SchemaValidationEntity.second]
            )
        )

        #expect(
            throws: SchemaError.duplicateIndexName(
                indexName: "duplicate_index",
                existingFields: ["first"],
                duplicateFields: ["second"]
            )
        ) {
            try Schema(
                [SchemaValidationEntity.self],
                indexDescriptors: [first, second]
            )
        }
    }

    @Test("Valid declarations produce a complete schema catalog")
    func validDeclarationsProduceSchemaCatalog() throws {
        let schema = try Schema([SchemaValidationEntity.self])

        #expect(schema.entities.map(\.name) == ["SchemaValidationEntity"])
        #expect(schema.entity(for: SchemaValidationEntity.self) != nil)
        #expect(schema.indexDescriptors.isEmpty)
        #expect(schema.allIndexNames.isEmpty)
    }
}
