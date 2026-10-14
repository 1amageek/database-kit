/// A task-local builder edge, not a retained JSONB semantic value.
package struct QueryJSONBIndexedMember: Sendable {
    package let key: String
    package let value: Int

    package init(key: String, value: Int) {
        self.key = key
        self.value = value
    }
}
