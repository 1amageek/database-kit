public enum DatabaseRDFTermCodecError: Error, Sendable, Equatable {
    case truncated
    case trailingBytes
    case unknownTag(UInt8)
    case invalidUTF8
    case invalidIRI(DatabaseRDFIRIError)
    case invalidBlankNodeIdentifier
    case invalidTripleSubject
    case invalidTriplePredicate
    case invalidDatatypeIRI
    case invalidLanguageTag
    case nonCanonicalLanguageTag
    case invalidLiteralAnnotation(UInt8)
    case invalidDirection(UInt8)
    case invalidRole(
        expected: DatabaseRDFTermRole,
        actual: DatabaseRDFTermKind
    )
    case nonCanonicalVarint
    case nonCanonicalStringEncoding
    case byteCountOverflow
    case maximumBytesExceeded(actual: Int, maximum: Int)
    case maximumDepthExceeded(actual: Int, maximum: Int)
    case maximumObjectCountExceeded(actual: Int, maximum: Int)
}
