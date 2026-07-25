import DatabaseTypes
import DatabaseKit
import DatabaseKit
import Testing

@Suite("Canonical database references")
struct PersistableReferenceTests {
    @Test("References round-trip as canonical record identities")
    func recordRoundTrip() throws {
        let firstIdentity = try EntityReference(
            entity: ReferenceTargetModel.persistableType,
            id: .string("target-1"),
            partitions: try FieldObject([
                (key: "tenantID", value: .string("tenant-a")),
            ])
        )
        let secondIdentity = try EntityReference(
            entity: ReferenceTargetModel.persistableType,
            id: .string("target-2"),
            partitions: try FieldObject([
                (key: "tenantID", value: .string("tenant-a")),
            ])
        )
        let first = try PersistableReference<ReferenceTargetModel>(identity: firstIdentity)
        let second = try PersistableReference<ReferenceTargetModel>(identity: secondIdentity)
        let owner = ReferenceOwnerModel(
            required: first,
            optional: nil,
            many: [first, second]
        )

        let fields = try PersistableFieldEncoder.encode(owner)
        let values = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) })

        #expect(values["required"] == .reference(firstIdentity))
        #expect(values["optional"] == .null)
        #expect(values["many"] == .array([
            .reference(firstIdentity),
            .reference(secondIdentity),
        ]))

        let decoded = try ReferenceOwnerModel.decodePersistedFields(fields)
        #expect(decoded.required == first)
        #expect(decoded.optional == nil)
        #expect(decoded.many == [first, second])
    }

    @Test("Reference rejects a mismatched target entity")
    func rejectsMismatchedEntity() throws {
        #expect(throws: PersistableReferenceError.self) {
            try PersistableReference<ReferenceTargetModel>(
                identity: try EntityReference(
                    entity: "Other",
                    id: .string("target-1")
                )
            )
        }
    }

    @Test("Relationship metadata is derived from typed fields")
    func relationshipMetadata() throws {
        let descriptors = ReferenceOwnerModel.relationshipDescriptors

        #expect(descriptors.count == 3)
        let required = try #require(descriptors.first { $0.propertyName == "required" })
        #expect(required.name == "ReferenceOwnerModel.required")
        #expect(required.ownerTypeName == ReferenceOwnerModel.persistableType)
        #expect(required.propertyFieldNumber == 2)
        #expect(required.relatedTypeName == ReferenceTargetModel.persistableType)
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
        #expect(try ReferenceOwnerModel.indexDescriptors.isEmpty)
    }
}
