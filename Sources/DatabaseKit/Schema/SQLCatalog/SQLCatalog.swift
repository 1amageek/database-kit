/// A validated, immutable declaration catalog, independent of persisted generations.
public struct SQLCatalog: Sendable, Hashable {
    public let namespaces: [SQLNamespace]
    public let relations: [SQLRelation]

    public init(namespaces: [SQLNamespace], relations: [SQLRelation]) throws(SQLCatalogError) {
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
        self.namespaces = namespaces
        self.relations = relations
    }
}
