import DatabaseKit
import DatabaseTypes

/// Errors raised by the canonical DatabaseWire representation.
public enum DatabaseWireError: Error, Sendable, Equatable {
    case truncated
    case byteCountOverflow
    case invalidBool(UInt8)
    case invalidUTF8
    case invalidTimestamp
    case trailingBytes
    case invalidMagic
    case unsupportedProtocolVersionValue(UInt16)
    case frameTooLarge(actual: Int, maximum: Int)
    case stringTooLarge(actual: Int, maximum: Int)
    case byteStringTooLarge(actual: Int, maximum: Int)
    case collectionTooLarge(actual: Int, maximum: Int)
    case nestingTooDeep(actual: Int, maximum: Int)
    case objectBudgetExceeded(actual: Int, maximum: Int)
    case unknownFieldType(UInt8)
    case invalidReferenceCardinality(UInt8)
    case invalidReferenceDeleteRule(UInt8)
    case invalidOperationIdentifier(UInt16)
    case unexpectedOperationIdentifier(
        expected: DatabaseOperationIdentifier,
        actual: DatabaseOperationIdentifier
    )
    case unexpectedRequestIdentifier(expected: UInt64, actual: UInt64)
    case invalidJobOperationFamily(UInt16)
    case invalidJobOperationKind
    case nonCanonicalJobOperationSet
    case mismatchedJobOperationIdentifier
    case invalidJobStatus
    case invalidJobCancellationResponse
    case invalidCommandAccess(UInt8)
    case invalidCommandIdentifier(CommandIdentifierError)
    case invalidMessageKind(UInt8)
    case invalidErrorCategory(UInt8)
    case invalidRetryability(UInt8)
    case invalidValueTag(UInt8)
    case invalidReferenceIdentifierTag(UInt8)
    case invalidReferenceIdentifier(ReferenceIdentifierValidationError)
    case invalidEntityReference(EntityReferenceError)
    case invalidCivilDate(CivilDateError)
    case invalidCivilTime(CivilTimeError)
    case invalidTimeSpan(TimeSpanError)
    case invalidGeographicPoint(GeographicPointError)
    case invalidGeographicPosition(GeographicPositionError)
    case invalidVector(VectorError)
    case invalidFieldObject(FieldObjectError)
    case nonCanonicalFieldObject
    case invalidFieldValueWireState
    case invalidNestingState
    case invalidQueryLanguage(UInt8)
    case invalidQueryInput(UInt8)
    case invalidResultPayload(UInt8)
    case invalidRowValueCount(expected: Int, actual: Int)
    case invalidDigestLength(actual: Int, expected: Int)
    case unsupportedSchemaManifestVersion(UInt16)
    case invalidSchemaManifest(String)
    case invalidSchemaExecutionInvocation(UInt8)
    case invalidSchemaExecutionResponse(UInt8)
    case invalidSchemaCompatibility(UInt8)
    case duplicateSchemaMapKey(context: String, key: String)
    case invalidParameterReference(UInt8)
    case invalidParameterPosition(UInt32)
    case emptyParameterName
    case nonCanonicalQueryParameterMap
    case emptySPARQLUpdateRequest
    case invalidSPARQLVariableName(String)
    case invalidRDFIRI(String)
    case invalidRDFBlankNodeIdentifier
    case invalidRDFTripleSubject
    case invalidRDFTriplePredicate
    case invalidRDFGraphName
    case invalidRDFPredicateIRI(String)
    case invalidRDFDatatypeIRI
    case invalidRDFLanguageTag
    case nonCanonicalRDFLanguageTag
    case invalidRDFLiteralAnnotation(UInt8)
    case invalidRDFDirection(UInt8)
    case invalidRDFDirectionValue(String)
    case invalidCanonicalRDFTerm(RDFTermWireError)
    case invalidSHACLPath(SHACLPathError)
    case invalidSHACLPathWireState
    case invalidPropertyPathNegatedSet
    case nonCanonicalPropertyPathPredicateSet
    case invalidPropertyPathRange(minimum: Int, maximum: Int?)
    case invalidGraphProgress
    case invalidGraphResult
    case invalidQueryIRWireState
}
