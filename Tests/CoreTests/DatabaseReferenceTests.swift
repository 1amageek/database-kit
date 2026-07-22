import Core
import DatabaseValue
import Relationship
import Testing

@Suite("Canonical database references")
struct DatabaseReferenceTests {
    @Test("References round-trip as canonical record identities")
    func recordRoundTrip() throws {
        let firstIdentity = RecordIdentity(
            entity: DatabaseReferenceTarget.persistableType,
            id: .string("target-1"),
            partitions: [
                DatabaseObjectField(
                    number: 2,
                    name: "tenantID",
                    value: .string("tenant-a")
                )
            ]
        )
        let secondIdentity = RecordIdentity(
            entity: DatabaseReferenceTarget.persistableType,
            id: .string("target-2")
        )
        let first = try DatabaseReference<DatabaseReferenceTarget>(identity: firstIdentity)
        let second = try DatabaseReference<DatabaseReferenceTarget>(identity: secondIdentity)
        let owner = DatabaseReferenceOwner(
            required: first,
            optional: nil,
            many: [first, second]
        )

        let fields = try DatabaseRecordEncoder.encode(owner)
        let values = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) })

        #expect(values["required"] == .reference(firstIdentity))
        #expect(values["optional"] == .null)
        #expect(values["many"] == .array([
            .reference(firstIdentity),
            .reference(secondIdentity),
        ]))

        let decoded = try DatabaseReferenceOwner.decodeDatabaseRecord(fields)
        #expect(decoded.required == first)
        #expect(decoded.optional == nil)
        #expect(decoded.many == [first, second])
    }

    @Test("Reference rejects a mismatched target entity")
    func rejectsMismatchedEntity() {
        #expect(throws: DatabaseReferenceError.self) {
            try DatabaseReference<DatabaseReferenceTarget>(
                identity: RecordIdentity(entity: "Other", id: .string("target-1"))
            )
        }
    }

    @Test("Relationship metadata is derived from typed fields")
    func relationshipMetadata() throws {
        let descriptors = DatabaseReferenceOwner.relationshipDescriptors

        #expect(descriptors.count == 3)
        let required = try #require(descriptors.first { $0.propertyName == "required" })
        #expect(required.name == "DatabaseReferenceOwner.required")
        #expect(required.ownerTypeName == DatabaseReferenceOwner.persistableType)
        #expect(required.propertyFieldNumber == 2)
        #expect(required.relatedTypeName == DatabaseReferenceTarget.persistableType)
        #expect(required.cardinality == .requiredToOne)
        #expect(required.deleteRule == .deny)

        let optional = try #require(descriptors.first { $0.propertyName == "optional" })
        #expect(optional.propertyFieldNumber == 3)
        #expect(optional.cardinality == .optionalToOne)
        #expect(optional.deleteRule == .nullify)

        let many = try #require(descriptors.first { $0.propertyName == "many" })
        #expect(many.propertyFieldNumber == 4)
        #expect(many.cardinality == .toMany)
        #expect(many.deleteRule == .cascade)
        #expect(DatabaseReferenceOwner.indexDescriptors.isEmpty)
    }
}
