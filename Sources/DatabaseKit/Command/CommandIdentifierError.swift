public enum CommandIdentifierError: Error, Sendable, Equatable {
    case empty
    case tooLong(actualUTF8Bytes: Int, maximumUTF8Bytes: Int)
    case invalidStart(UInt8)
    case invalidByte(UInt8)
    case adjacentSeparator
    case trailingSeparator
}
