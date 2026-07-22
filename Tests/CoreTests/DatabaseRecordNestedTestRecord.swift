import Core

@Persistable
struct DatabaseRecordNestedTestRecord {
    var value: DatabaseRecordNestedValue
    var history: [DatabaseRecordNestedValue]
}
