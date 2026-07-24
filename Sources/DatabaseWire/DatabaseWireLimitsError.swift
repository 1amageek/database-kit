import DatabaseTypes
public enum DatabaseWireLimitsError: Error, Sendable, Equatable {
    case negativeValue(limit: DatabaseWireLimit, value: Int)
    case nestingDepthExceedsSupportedMaximum(actual: Int, maximum: Int)
}
