public enum DatabaseRDFIRIError: Error, Sendable, Equatable {
    case missingScheme
    case invalidScheme(byteOffset: Int)
    case invalidPercentEncoding(byteOffset: Int)
    case invalidCharacter(byteOffset: Int)
    case invalidAuthority
    case invalidIPLiteral
    case forbiddenBidirectionalFormattingCharacter(
        scalar: UInt32,
        byteOffset: Int
    )
}
