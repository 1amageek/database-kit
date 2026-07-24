public enum ULIDError: Error, Sendable, Equatable {
    case invalidByteCount(actual: Int)
    case invalidRandomnessByteCount(actual: Int)
    case timestampOutOfRange(UInt64)
}
