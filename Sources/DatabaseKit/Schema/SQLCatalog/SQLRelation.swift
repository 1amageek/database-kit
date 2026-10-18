/// A logical relation bound to one physical entity; key execution is runtime-owned.
public struct SQLRelation: Sendable, Hashable {
    public let id: String
    public let namespaceID: String
    public let name: String
    public let entityName: String
    public let columns: [SQLColumn]
    public let primaryKeyColumnIDs: [String]?
    public let primaryKeyConstraint: SQLConstraintAttributes?
    public let constraints: [SQLConstraint]
    public let fieldNumberHighWaterMark: Int

    public init(
        id: String,
        namespaceID: String,
        name: String,
        entityName: String,
        columns: [SQLColumn],
        primaryKeyColumnIDs: [String]? = nil,
        primaryKeyConstraint: SQLConstraintAttributes? = nil,
        constraints: [SQLConstraint] = [],
        fieldNumberHighWaterMark: Int? = nil
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
            if let number = column.fieldNumber, !fieldNumbers.insert(number).inserted {
                throw .duplicateFieldNumber(number)
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
        let primaryAttributes: SQLConstraintAttributes?
        if primaryKeyColumnIDs != nil {
            if let primaryKeyConstraint {
                primaryAttributes = primaryKeyConstraint
            } else {
                primaryAttributes = try SQLConstraintAttributes(id: id + ":primary-key", name: name + "_pkey")
            }
        } else {
            guard primaryKeyConstraint == nil else { throw .primaryKeyAttributesWithoutKey }
            primaryAttributes = nil
        }
        var constraintIDs: Set<SQLIdentifier> = []
        var constraintNames: Set<SQLIdentifier> = []
        if let primaryAttributes {
            constraintIDs.insert(SQLIdentifier(value: primaryAttributes.id))
            constraintNames.insert(SQLIdentifier(value: primaryAttributes.name))
        }
        for constraint in constraints {
            guard constraintIDs.insert(SQLIdentifier(value: constraint.id)).inserted else {
                throw .duplicateConstraintID(constraint.id)
            }
            guard constraintNames.insert(SQLIdentifier(value: constraint.name)).inserted else {
                throw .duplicateConstraintName(constraint.name)
            }
            let references: [String]
            switch constraint.kind {
            case .unique(let ids, _): references = ids
            case .notNull(let id): references = [id]
            case .foreignKey(let key): references = key.columnIDs
            case .check: references = []
            }
            for reference in references where !columnIDs.contains(SQLIdentifier(value: reference)) {
                throw .unknownConstraintColumnID(reference)
            }
        }
        let maximumField = fieldNumbers.max() ?? 0
        let highWater = fieldNumberHighWaterMark ?? maximumField
        guard highWater >= maximumField, highWater >= 0 else { throw .invalidFieldNumberHighWaterMark(highWater) }
        self.fieldNumberHighWaterMark = highWater
        self.primaryKeyConstraint = primaryAttributes
        self.constraints = constraints
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
            && lhs.fieldNumberHighWaterMark == rhs.fieldNumberHighWaterMark
            && lhs.primaryKeyConstraint == rhs.primaryKeyConstraint
            && lhs.constraints == rhs.constraints
            && SQLIdentifier.equal(lhs.primaryKeyColumnIDs, rhs.primaryKeyColumnIDs)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(SQLIdentifier(value: id))
        hasher.combine(SQLIdentifier(value: namespaceID))
        hasher.combine(SQLIdentifier(value: name))
        hasher.combine(SQLIdentifier(value: entityName))
        hasher.combine(columns)
        hasher.combine(fieldNumberHighWaterMark)
        hasher.combine(primaryKeyConstraint)
        hasher.combine(constraints)
        hasher.combine(primaryKeyColumnIDs?.count)
        if let primaryKeyColumnIDs {
            for columnID in primaryKeyColumnIDs {
                hasher.combine(SQLIdentifier(value: columnID))
            }
        }
    }
}
