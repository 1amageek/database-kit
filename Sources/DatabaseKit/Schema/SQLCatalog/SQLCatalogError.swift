/// An intrinsic logical SQL catalog declaration failure.
public enum SQLCatalogError: Error, Sendable, Equatable {
    case emptyIdentifier
    case nulInIdentifier
    case invalidFieldNumber(Int)
    case duplicateNamespaceID(String)
    case duplicateNamespaceName(String)
    case duplicateRelationID(String)
    case duplicateRelationName(namespaceID: String, name: String)
    case unknownNamespaceID(String)
    case duplicateEntityName(String)
    case duplicateColumnID(String)
    case duplicateColumnName(String)
    case duplicateFieldNumber(Int)
    case emptyPrimaryKey
    case duplicatePrimaryKeyColumnID(String)
    case unknownPrimaryKeyColumnID(String)
}
