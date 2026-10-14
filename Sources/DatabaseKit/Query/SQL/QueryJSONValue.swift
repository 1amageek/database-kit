import DatabaseTypes

/// Validated lexical JSON retaining the original bytes and their owner.
public struct QueryJSONValue: Sendable, Hashable {
    public let bytes: ByteString
    private let footprint: QueryValueFootprint

    public init(bytes: ByteString, limits: QueryValueLimits) throws(QueryValueError) {
        footprint = try QueryJSONParser.validate(bytes: bytes, limits: limits)
        self.bytes = bytes
    }
    public func measure() throws(QueryValueError) -> QueryValueFootprint { footprint }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.bytes == rhs.bytes }

    public func hash(into hasher: inout Hasher) { hasher.combine(bytes) }
}
