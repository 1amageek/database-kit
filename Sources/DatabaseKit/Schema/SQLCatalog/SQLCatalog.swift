/// A validated, immutable declaration catalog, independent of persisted generations.
public struct SQLCatalog: Sendable, Hashable {
    public let namespaces: [SQLNamespace]
    public let relations: [SQLRelation]
    public let sequences: [SQLSequence]

    public init(namespaces: [SQLNamespace], relations: [SQLRelation], sequences: [SQLSequence] = []) throws(SQLCatalogError) {
        var namespaceIDs: Set<SQLIdentifier> = []
        var namespaceNames: Set<SQLIdentifier> = []
        for namespace in namespaces {
            guard namespaceIDs.insert(SQLIdentifier(value: namespace.id)).inserted else {
                throw .duplicateNamespaceID(namespace.id)
            }
            guard namespaceNames.insert(SQLIdentifier(value: namespace.name)).inserted else {
                throw .duplicateNamespaceName(namespace.name)
            }
        }
        var relationIDs: Set<SQLIdentifier> = []
        var namesByNamespace: [SQLIdentifier: Set<SQLIdentifier>] = [:]
        var entityNames: Set<SQLIdentifier> = []
        for relation in relations {
            guard relationIDs.insert(SQLIdentifier(value: relation.id)).inserted else {
                throw .duplicateRelationID(relation.id)
            }
            let namespaceID = SQLIdentifier(value: relation.namespaceID)
            guard namespaceIDs.contains(namespaceID) else {
                throw .unknownNamespaceID(relation.namespaceID)
            }
            guard namesByNamespace[namespaceID, default: []]
                .insert(SQLIdentifier(value: relation.name)).inserted else {
                throw .duplicateRelationName(namespaceID: relation.namespaceID, name: relation.name)
            }
            guard entityNames.insert(SQLIdentifier(value: relation.entityName)).inserted else {
                throw .duplicateEntityName(relation.entityName)
            }
        }
        let relationsByID = Dictionary(uniqueKeysWithValues: relations.map { (SQLIdentifier(value: $0.id), $0) })
        for relation in relations {
            for constraint in relation.constraints {
                guard case .foreignKey(let key) = constraint.kind else { continue }
                guard let target = relationsByID[SQLIdentifier(value: key.referencedRelationID)] else {
                    throw .unknownReferencedRelationID(key.referencedRelationID)
                }
                guard let targetIDs = key.referencedColumnIDs ?? target.primaryKeyColumnIDs,
                      targetIDs.count == key.columnIDs.count else { throw .invalidForeignKeyArity }
                let targetColumns = Set(target.columns.map { SQLIdentifier(value: $0.id) })
                for id in targetIDs where !targetColumns.contains(SQLIdentifier(value: id)) {
                    throw .unknownReferencedColumnID(id)
                }
                let targetSet = Set(targetIDs.map { SQLIdentifier(value: $0) })
                let primaryMatches = target.primaryKeyColumnIDs.map {
                    Set($0.map { SQLIdentifier(value: $0) }) == targetSet
                } == true
                    && target.primaryKeyConstraint?.timing == .immediate
                let uniqueMatches = target.constraints.contains { candidate in
                    guard candidate.timing == .immediate,
                          case .unique(let columns, _) = candidate.kind else { return false }
                    return Set(columns.map { SQLIdentifier(value: $0) }) == targetSet
                }
                guard primaryMatches || uniqueMatches else { throw .invalidForeignKeyTarget(target.id) }
            }
        }
        var sequenceIDs: Set<SQLIdentifier> = []
        for sequence in sequences {
            guard sequenceIDs.insert(SQLIdentifier(value: sequence.id)).inserted else {
                throw .duplicateSequenceID(sequence.id)
            }
            let namespace = SQLIdentifier(value: sequence.namespaceID)
            guard namespaceIDs.contains(namespace) else { throw .unknownNamespaceID(sequence.namespaceID) }
            guard namesByNamespace[namespace, default: []].insert(SQLIdentifier(value: sequence.name)).inserted else {
                throw .duplicateSequenceName(namespaceID: sequence.namespaceID, name: sequence.name)
            }
            if let owner = sequence.ownedBy {
                guard let relation = relationsByID[SQLIdentifier(value: owner.relationID)],
                      let column = relation.columns.first(where: { SQLIdentifier(value: $0.id) == SQLIdentifier(value: owner.columnID) }),
                      column.fieldNumber != nil else { throw .unknownSequenceOwner }
                if case .identity(let identity) = column.policy,
                   SQLIdentifier(value: identity.sequenceID) != SQLIdentifier(value: sequence.id) {
                    throw .conflictingSequenceOwner(sequence.id)
                }
            }
        }
        let sequencesByID = Dictionary(uniqueKeysWithValues: sequences.map { (SQLIdentifier(value: $0.id), $0) })
        for relation in relations {
            for column in relation.columns {
                guard case .identity(let identity) = column.policy else { continue }
                guard let sequence = sequencesByID[SQLIdentifier(value: identity.sequenceID)] else {
                    throw .unknownSequenceID(identity.sequenceID)
                }
                if let owner = sequence.ownedBy,
                   SQLIdentifier(value: owner.relationID) != SQLIdentifier(value: relation.id)
                    || SQLIdentifier(value: owner.columnID) != SQLIdentifier(value: column.id) {
                    throw .conflictingSequenceOwner(sequence.id)
                }
            }
        }
        self.sequences = sequences
        self.namespaces = namespaces
        self.relations = relations
    }
}
