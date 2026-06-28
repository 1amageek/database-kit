public enum DatabaseWireKeyValueOperation: Sendable, Hashable {
    case get(key: [UInt8])
    case range(begin: [UInt8], end: [UInt8], limit: Int, reverse: Bool)
    case set(key: [UInt8], value: [UInt8])
    case clear(key: [UInt8])
}
