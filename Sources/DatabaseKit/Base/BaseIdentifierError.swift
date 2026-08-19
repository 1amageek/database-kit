#if DATABASE_KIT_MULTI_BASE
public enum BaseIdentifierError: Error, Sendable, Equatable {
    case invalidUTF8ByteCount(actual: Int, maximum: Int)
    case invalidCharacter(byte: UInt8, offset: Int)
    case emptySegment(offset: Int)
    case invalidSegmentBoundary(byte: UInt8, offset: Int)
}

#endif
