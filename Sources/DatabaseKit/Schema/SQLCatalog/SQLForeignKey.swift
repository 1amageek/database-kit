/// An immutable ordered foreign key and its referential actions.
public struct SQLForeignKey: Sendable, Hashable {
    public let columnIDs: [String]
    public let referencedRelationID: String
    public let referencedColumnIDs: [String]?
    public let referencedUniqueIndexID: String?
    public let onDeleteColumnIDs: [String]?
    public let match: SQLForeignKeyMatch
    public let onUpdate: SQLReferentialAction
    public let onDelete: SQLReferentialAction

    public init(columnIDs: [String], referencedRelationID: String,
                referencedColumnIDs: [String]? = nil, match: SQLForeignKeyMatch = .simple,
                onUpdate: SQLReferentialAction = .noAction, onDelete: SQLReferentialAction = .noAction,
                onDeleteColumnIDs: [String]? = nil,
                referencedUniqueIndexID: String? = nil) throws(SQLCatalogError) {
        try SQLIdentifier.validateColumnIDs(columnIDs)
        try SQLIdentifier.validate(referencedRelationID)
        if let referencedUniqueIndexID { try SQLIdentifier.validate(referencedUniqueIndexID) }
        if let referencedColumnIDs {
            try SQLIdentifier.validateColumnIDs(referencedColumnIDs)
            guard referencedColumnIDs.count == columnIDs.count else { throw .invalidForeignKeyArity }
        }
        if let onDeleteColumnIDs {
            try SQLIdentifier.validateColumnIDs(onDeleteColumnIDs)
            guard onDelete == .setNull || onDelete == .setDefault else {
                throw .invalidReferentialActionColumns
            }
            let sources = Set(columnIDs.map { SQLIdentifier(value: $0) })
            guard onDeleteColumnIDs.allSatisfy({ sources.contains(SQLIdentifier(value: $0)) }) else {
                throw .invalidReferentialActionColumns
            }
        }
        self.columnIDs = columnIDs
        self.referencedRelationID = referencedRelationID
        self.referencedColumnIDs = referencedColumnIDs
        self.referencedUniqueIndexID = referencedUniqueIndexID
        self.onDeleteColumnIDs = onDeleteColumnIDs
        self.match = match
        self.onUpdate = onUpdate
        self.onDelete = onDelete
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLIdentifier.equal(lhs.columnIDs, rhs.columnIDs)
            && SQLIdentifier(value: lhs.referencedRelationID) == SQLIdentifier(value: rhs.referencedRelationID)
            && SQLIdentifier.equal(lhs.referencedColumnIDs, rhs.referencedColumnIDs)
            && ExpressionIdentity.nameEqual(lhs.referencedUniqueIndexID, rhs.referencedUniqueIndexID)
            && SQLIdentifier.equal(lhs.onDeleteColumnIDs, rhs.onDeleteColumnIDs)
            && lhs.match == rhs.match && lhs.onUpdate == rhs.onUpdate && lhs.onDelete == rhs.onDelete
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(SQLIdentifier(value: referencedRelationID))
        ExpressionIdentity.hashName(referencedUniqueIndexID, into: &hasher)
        for ids in [Optional(columnIDs), referencedColumnIDs, onDeleteColumnIDs] {
            hasher.combine(ids?.count)
            if let ids { for id in ids { hasher.combine(SQLIdentifier(value: id)) } }
        }
        hasher.combine(match); hasher.combine(onUpdate); hasher.combine(onDelete)
    }
}
