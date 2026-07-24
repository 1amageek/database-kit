public enum ULIDError: Error, Sendable, Equatable {
    case invalidByteCount(actual: Int)
}
