/// A task-local builder edge, not a retained JSONB semantic value.
public struct QueryJSONBIndexedMember: Sendable {
    public let key: String
    public let value: Int

    public init(key: String, value: Int) {
        self.key = key
        self.value = value
    }
}
