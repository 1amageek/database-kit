import DatabaseTypes
import DatabaseKit

@Persistable
struct PersistableFieldNestedTestDocument {
    var id: String = "fixture-id"
    var value: PersistableFieldNestedValue
    var history: [PersistableFieldNestedValue]
}
