import DatabaseTypes
import DatabaseKit
import DatabaseKit

@Persistable
struct ReferenceOwnerModel {
    var id: String = "fixture-id"
    @Relationship(deleteRule: .deny)
    var required: PersistableReference<ReferenceTargetModel>

    @Relationship
    var optional: PersistableReference<ReferenceTargetModel>?

    @Relationship(deleteRule: .cascade)
    var many: [PersistableReference<ReferenceTargetModel>]
}
