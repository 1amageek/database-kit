/// Immutable canonical members retaining the complete flat JSONB owner.
public struct QueryJSONBMembers: Sendable, RandomAccessCollection {
    public typealias Index = Int
    public typealias Element = QueryJSONBMember
    let storage: QueryJSONBStorage
    let range: Range<Int>

    init(storage: QueryJSONBStorage, range: Range<Int>) {
        self.storage = storage
        self.range = range
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { range.count }
    public func index(after index: Int) -> Int { index + 1 }
    public func index(before index: Int) -> Int { index - 1 }
    public subscript(index: Int) -> QueryJSONBMember {
        precondition(index >= 0 && index < endIndex)
        let member = storage.members[range.lowerBound + index]
        return QueryJSONBMember(key: member.key, value: storage.node(at: member.value))
    }
}
