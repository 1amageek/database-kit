import DatabaseTypes
import DatabaseKit

@Persistable
struct DeclarationPrincipal {
    #Directory<DeclarationPrincipal>("declaration-principals")

    var id: String
    var displayName: String
}
