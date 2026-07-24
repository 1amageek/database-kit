import DatabaseTypes
import DatabaseKit

@Persistable
struct ReferenceTargetModel {
    var id: String = "fixture-id"
    #Directory<ReferenceTargetModel>(
        "targets",
        Field<ReferenceTargetModel>(\.tenantID)
    )

    var tenantID: String
    var name: String
}
