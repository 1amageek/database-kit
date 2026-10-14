/// Immutable children retaining the complete flat JSONB owner.
public struct QueryJSONBElements: Sendable, RandomAccessCollection {
    public typealias Index = Int
    public typealias Element = QueryJSONBNode
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
    public subscript(index: Int) -> QueryJSONBNode {
        precondition(index >= 0 && index < endIndex)
        return storage.node(at: storage.elements[range.lowerBound + index])
    }
}
