import DatabaseTypes
import DatabaseKit
import DatabaseKit

@Persistable
struct DatabaseReferenceOwner {
    @Relationship(deleteRule: .deny)
    var required: DatabaseReference<DatabaseReferenceTarget>

    @Relationship
    var optional: DatabaseReference<DatabaseReferenceTarget>?

    @Relationship(deleteRule: .cascade)
    var many: [DatabaseReference<DatabaseReferenceTarget>]
}
