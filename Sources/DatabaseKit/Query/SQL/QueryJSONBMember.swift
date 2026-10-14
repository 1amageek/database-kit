/// An immutable key and value in a canonical JSONB object.
public struct QueryJSONBMember: Sendable, Hashable {
    public let key: String
    public let value: QueryJSONBNode

    public init(key: String, value: QueryJSONBNode) {
        self.key = key
        self.value = value
    }
}

extension QueryJSONBMember {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key.utf8.elementsEqual(rhs.key.utf8) && lhs.value == rhs.value
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(key.utf8.count)
        for byte in key.utf8 { hasher.combine(byte) }
        hasher.combine(value)
    }
}
