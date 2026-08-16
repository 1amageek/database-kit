public enum SchemaFingerprintError: Error, Sendable, Equatable {
    case invalidByteCount(actual: Int, expected: Int)
    case canonicalRepresentationUnavailable
}
