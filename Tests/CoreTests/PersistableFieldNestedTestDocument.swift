import DatabaseTypes
import DatabaseValue
import Core

@Persistable
struct PersistableFieldNestedTestDocument {
    var value: PersistableFieldNestedValue
    var history: [PersistableFieldNestedValue]
}
