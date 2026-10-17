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
    case emptyConstraintColumns
    case duplicateConstraintColumnID(String)
    case unknownConstraintColumnID(String)
    case duplicateConstraintID(String)
    case duplicateConstraintName(String)
    case invalidConstraintTiming(String)
    case primaryKeyAttributesWithoutKey
    case invalidForeignKeyArity
    case invalidReferentialActionColumns
    case unknownReferencedRelationID(String)
    case unknownReferencedColumnID(String)
    case invalidForeignKeyTarget(String)
    case invalidColumnPolicy(String)
    case invalidColumnType(String)
    case duplicateSequenceID(String)
    case duplicateSequenceName(namespaceID: String, name: String)
    case invalidSequenceIncrement
    case invalidSequenceBounds
    case invalidSequenceStart
    case unknownSequenceID(String)
    case unknownSequenceOwner
    case conflictingSequenceOwner(String)
    case invalidConstraintSelection
}
