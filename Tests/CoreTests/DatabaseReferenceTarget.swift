import DatabaseTypes
import DatabaseValue
import Core

@Persistable
struct DatabaseReferenceTarget {
    #Directory<DatabaseReferenceTarget>(
        "targets",
        Field<DatabaseReferenceTarget>(\.tenantID)
    )

    var tenantID: String
    var name: String
}
