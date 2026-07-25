/// An intrinsic validity failure in an entity schema catalog.
///
/// `Schema.Entity` validates these invariants at every construction boundary so
/// encoders, decoders, migration tools, and runtimes never receive ambiguous
/// field or index metadata.
public enum SchemaEntityError: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyEntityName
    case emptyFieldName(fieldNumber: Int)
    case invalidFieldNumber(fieldName: String, fieldNumber: Int)
    case duplicateFieldName(String)
    case duplicateFieldNumber(fieldNumber: Int, fieldNames: [String])
    case invalidReferenceTarget(fieldName: String)
    case missingReferenceTarget(fieldName: String)
    case referenceTargetOnNonReferenceField(fieldName: String)
    case emptyDirectoryPathComponent(position: Int)
    case unknownDirectoryField(String)
    case partitionDirectoryRequiresDynamicField
    case invalidIndexEntity(
        indexName: String,
        expected: String,
        actual: String
    )
    case emptyIndexName
    case duplicateIndexName(String)
    case emptyIndexKindIdentifier(indexName: String)
    case emptyIndexFieldName(indexName: String)
    case unknownIndexField(indexName: String, fieldName: String)
    case unknownStoredField(indexName: String, fieldName: String)
    case invalidIndexDeclaration(IndexDeclarationError)
    case unknownEnumField(String)
    case enumMetadataOnNonEnumField(String)
    case emptyEnumCase(fieldName: String)
    case duplicateEnumCase(fieldName: String, caseName: String)
    case invalidRelationshipOwner(
        relationship: String,
        expected: String,
        actual: String
    )
    case duplicateRelationshipName(String)
    case emptyRelationshipTarget(String)
    case invalidRelationshipField(
        relationship: String,
        fieldName: String,
        fieldNumber: UInt32
    )
    case relationshipOnNonReferenceField(
        relationship: String,
        fieldName: String
    )
    case relationshipTargetMismatch(
        relationship: String,
        fieldTarget: String,
        relationshipTarget: String
    )
    case invalidFieldAccessRule(fieldName: String, fieldNumber: Int)
    case duplicateFieldAccessRule(String)
    case unknownObjectPropertyField(String)
    case emptyOntologyIRI
    case emptyDataPropertyIRI
    case duplicateDataPropertyIRI(String)
    case emptyPolymorphicGroupIdentifier
    case invalidPolymorphicDirectoryComponent(position: Int)

    public var description: String {
        switch self {
        case .emptyEntityName:
            return "Entity name must not be empty."
        case .emptyFieldName(let fieldNumber):
            return "Field #\(fieldNumber) has an empty name."
        case .invalidFieldNumber(let fieldName, let fieldNumber):
            return "Field '\(fieldName)' has invalid field number \(fieldNumber); field numbers must be positive."
        case .duplicateFieldName(let fieldName):
            return "Field name '\(fieldName)' is declared more than once."
        case .duplicateFieldNumber(let fieldNumber, let fieldNames):
            return "Field number \(fieldNumber) is shared by fields [\(fieldNames.joined(separator: ", "))]."
        case .invalidReferenceTarget(let fieldName):
            return "Reference field '\(fieldName)' has an empty target entity."
        case .missingReferenceTarget(let fieldName):
            return "Reference field '\(fieldName)' must declare its target entity."
        case .referenceTargetOnNonReferenceField(let fieldName):
            return "Non-reference field '\(fieldName)' declares a reference target entity."
        case .emptyDirectoryPathComponent(let position):
            return "Directory path component at position \(position) is empty."
        case .unknownDirectoryField(let fieldName):
            return "Directory path references unknown field '\(fieldName)'."
        case .partitionDirectoryRequiresDynamicField:
            return "A partition directory requires at least one dynamic field."
        case .invalidIndexEntity(let indexName, let expected, let actual):
            return "Index '\(indexName)' belongs to entity '\(actual)', expected '\(expected)'."
        case .emptyIndexName:
            return "Index name must not be empty."
        case .duplicateIndexName(let indexName):
            return "Index name '\(indexName)' is declared more than once on the entity."
        case .emptyIndexKindIdentifier(let indexName):
            return "Index '\(indexName)' has an empty kind identifier."
        case .emptyIndexFieldName(let indexName):
            return "Index '\(indexName)' contains an empty field name."
        case .unknownIndexField(let indexName, let fieldName):
            return "Index '\(indexName)' references unknown field '\(fieldName)'."
        case .unknownStoredField(let indexName, let fieldName):
            return "Index '\(indexName)' stores unknown field '\(fieldName)'."
        case .invalidIndexDeclaration(let error):
            return error.description
        case .unknownEnumField(let fieldName):
            return "Enum metadata references unknown field '\(fieldName)'."
        case .enumMetadataOnNonEnumField(let fieldName):
            return "Enum metadata is attached to non-enum field '\(fieldName)'."
        case .emptyEnumCase(let fieldName):
            return "Enum field '\(fieldName)' contains an empty case name."
        case .duplicateEnumCase(let fieldName, let caseName):
            return "Enum field '\(fieldName)' declares case '\(caseName)' more than once."
        case .invalidRelationshipOwner(let relationship, let expected, let actual):
            return "Relationship '\(relationship)' belongs to '\(actual)', expected '\(expected)'."
        case .duplicateRelationshipName(let relationship):
            return "Relationship '\(relationship)' is declared more than once."
        case .emptyRelationshipTarget(let relationship):
            return "Relationship '\(relationship)' has an empty target entity."
        case .invalidRelationshipField(let relationship, let fieldName, let fieldNumber):
            return "Relationship '\(relationship)' references missing field '\(fieldName)' (#\(fieldNumber))."
        case .relationshipOnNonReferenceField(let relationship, let fieldName):
            return "Relationship '\(relationship)' is attached to non-reference field '\(fieldName)'."
        case .relationshipTargetMismatch(let relationship, let fieldTarget, let relationshipTarget):
            return "Relationship '\(relationship)' targets '\(relationshipTarget)', but its field targets '\(fieldTarget)'."
        case .invalidFieldAccessRule(let fieldName, let fieldNumber):
            return "Field access rule references missing field '\(fieldName)' (#\(fieldNumber))."
        case .duplicateFieldAccessRule(let fieldName):
            return "Field '\(fieldName)' declares more than one access rule."
        case .unknownObjectPropertyField(let fieldName):
            return "Object property metadata references unknown field '\(fieldName)'."
        case .emptyOntologyIRI:
            return "Ontology and object-property IRIs must not be empty."
        case .emptyDataPropertyIRI:
            return "Data-property IRIs must not be empty."
        case .duplicateDataPropertyIRI(let iri):
            return "Data-property IRI '\(iri)' is declared more than once."
        case .emptyPolymorphicGroupIdentifier:
            return "A polymorphic group identifier must not be empty."
        case .invalidPolymorphicDirectoryComponent(let position):
            return "Polymorphic directory component #\(position) must be a non-empty static path."
        }
    }
}
