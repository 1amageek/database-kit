/// Validated JSONB preserving exact numbers and their display scale.
public struct QueryJSONBValue: Sendable, Hashable {
    public let root: QueryJSONBNode
    private let footprint: QueryValueFootprint

    public init(json: QueryJSONValue, limits: QueryValueLimits) throws(QueryValueError) {
        root = try QueryJSONParser.decode(bytes: json.bytes, limits: limits)
        footprint = try QueryJSONParser.measure(root: root, limits: limits)
    }

    public init(root: QueryJSONBNode, limits: QueryValueLimits) throws(QueryValueError) {
        footprint = try QueryJSONParser.measure(root: root, limits: limits)
        self.root = root
    }

    public func measure() throws(QueryValueError) -> QueryValueFootprint { footprint }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.root == rhs.root }

    public func hash(into hasher: inout Hasher) { hasher.combine(root) }
}
