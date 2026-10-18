/// Pure declaration checks shared by resolved SQL metadata.
enum SQLCatalogMetadataValidation {
    static func columns(_ values: [(String, String)]) throws(SQLCatalogError) {
        var ids: Set<SQLIdentifier> = []
        var names: Set<SQLIdentifier> = []
        for (id, name) in values {
            guard ids.insert(SQLIdentifier(value: id)).inserted else { throw .duplicateColumnID(id) }
            guard names.insert(SQLIdentifier(value: name)).inserted else { throw .duplicateColumnName(name) }
        }
    }
}
