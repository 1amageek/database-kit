/// An occurrence index meaningful only with its owning arena and statement root.
public struct QueryOccurrenceID: Sendable, Equatable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}
