import DatabaseValue

/// Errors raised by DatabaseKit wire binary codecs.
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
    case invalidJobOperationFamily(UInt16)
    case invalidJobOperationKind
    case nonCanonicalJobOperationSet
    case mismatchedJobOperationIdentifier
    case invalidCommandIdentifier(expected: String, actual: String)
    case invalidMessageKind(UInt8)
    case invalidErrorCategory(UInt8)
    case invalidRetryability(UInt8)
    case invalidValueTag(UInt8)
    case invalidRecordIdentifierTag(UInt8)
    case emptyRecordIdentifierComposite
    case invalidRecordIdentifier(RecordIdentifierValidationError)
    case invalidQueryLanguage(UInt8)
    case invalidQueryInput(UInt8)
    case invalidResultPayload(UInt8)
    case invalidDigestLength(actual: Int, expected: Int)
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
    case invalidRDFPredicateIRI(String)
    case invalidRDFDatatypeIRI
    case invalidRDFLanguageTag
    case nonCanonicalRDFLanguageTag
    case invalidRDFLiteralAnnotation(UInt8)
    case invalidRDFDirection(UInt8)
    case invalidRDFDirectionValue(String)
    case invalidCanonicalRDFTerm(DatabaseRDFTermCodecError)
    case invalidPropertyPathNegatedSet
    case nonCanonicalPropertyPathPredicateSet
    case invalidPropertyPathRange(minimum: Int, maximum: Int?)
    case invalidGraphProgress
    case invalidGraphResult
    case invalidQueryIRWireState
}
