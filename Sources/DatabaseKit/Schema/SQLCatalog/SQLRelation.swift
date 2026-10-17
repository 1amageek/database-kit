/// A logical relation bound to one physical entity; key execution is runtime-owned.
public struct SQLRelation: Sendable, Hashable {
    public let id: String
    public let namespaceID: String
    public let name: String
    public let entityName: String
    public let columns: [SQLColumn]
    public let primaryKeyColumnIDs: [String]?

    public init(
        id: String,
        namespaceID: String,
        name: String,
        entityName: String,
        columns: [SQLColumn],
        primaryKeyColumnIDs: [String]? = nil
    ) throws(SQLCatalogError) {
        try SQLIdentifier.validate(id)
        try SQLIdentifier.validate(namespaceID)
        try SQLIdentifier.validate(name)
        try SQLIdentifier.validate(entityName)
        var columnIDs: Set<SQLIdentifier> = []
        var columnNames: Set<SQLIdentifier> = []
        var fieldNumbers: Set<Int> = []
        for column in columns {
            guard columnIDs.insert(SQLIdentifier(value: column.id)).inserted else {
                throw .duplicateColumnID(column.id)
            }
            guard columnNames.insert(SQLIdentifier(value: column.name)).inserted else {
                throw .duplicateColumnName(column.name)
            }
            guard fieldNumbers.insert(column.fieldNumber).inserted else {
                throw .duplicateFieldNumber(column.fieldNumber)
            }
        }
        if let primaryKeyColumnIDs {
            guard !primaryKeyColumnIDs.isEmpty else { throw .emptyPrimaryKey }
            var keyIDs: Set<SQLIdentifier> = []
            for columnID in primaryKeyColumnIDs {
                try SQLIdentifier.validate(columnID)
                let identity = SQLIdentifier(value: columnID)
                guard keyIDs.insert(identity).inserted else {
                    throw .duplicatePrimaryKeyColumnID(columnID)
                }
                guard columnIDs.contains(identity) else {
                    throw .unknownPrimaryKeyColumnID(columnID)
                }
            }
        }
        self.id = id
        self.namespaceID = namespaceID
        self.name = name
        self.entityName = entityName
        self.columns = columns
        self.primaryKeyColumnIDs = primaryKeyColumnIDs
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLIdentifier(value: lhs.id) == SQLIdentifier(value: rhs.id)
            && SQLIdentifier(value: lhs.namespaceID) == SQLIdentifier(value: rhs.namespaceID)
            && SQLIdentifier(value: lhs.name) == SQLIdentifier(value: rhs.name)
            && SQLIdentifier(value: lhs.entityName) == SQLIdentifier(value: rhs.entityName)
            && lhs.columns == rhs.columns
            && SQLIdentifier.equal(lhs.primaryKeyColumnIDs, rhs.primaryKeyColumnIDs)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(SQLIdentifier(value: id))
        hasher.combine(SQLIdentifier(value: namespaceID))
        hasher.combine(SQLIdentifier(value: name))
        hasher.combine(SQLIdentifier(value: entityName))
        hasher.combine(columns)
        hasher.combine(primaryKeyColumnIDs?.count)
        if let primaryKeyColumnIDs {
            for columnID in primaryKeyColumnIDs {
                hasher.combine(SQLIdentifier(value: columnID))
            }
        }
    }
}
