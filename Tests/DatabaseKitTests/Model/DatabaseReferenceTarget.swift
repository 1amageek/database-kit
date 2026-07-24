import DatabaseTypes
import DatabaseKit

@Persistable
struct DatabaseReferenceTarget {
    #Directory<DatabaseReferenceTarget>(
        "targets",
        Field<DatabaseReferenceTarget>(\.tenantID)
    )

    var tenantID: String
    var name: String
}
