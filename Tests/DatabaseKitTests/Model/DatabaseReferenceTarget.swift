import DatabaseTypes
import DatabaseKit

@Persistable
struct DatabaseReferenceTarget {
    var id: String = "fixture-id"
    #Directory<DatabaseReferenceTarget>(
        "targets",
        Field<DatabaseReferenceTarget>(\.tenantID)
    )

    var tenantID: String
    var name: String
}
