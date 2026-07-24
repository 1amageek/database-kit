import DatabaseTypes
import DatabaseKit

@Persistable
struct PersistableFieldNestedTestDocument {
    var value: PersistableFieldNestedValue
    var history: [PersistableFieldNestedValue]
}
