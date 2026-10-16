public struct QueryValueElements: Sendable, RandomAccessCollection {
    public typealias Index = Int
    public typealias Element = QueryValue
    let storage: QueryValueStorage
    let range: Range<Int>

    public var startIndex: Int { 0 }
    public var endIndex: Int { range.count }
    public func index(after index: Int) -> Int { index + 1 }
    public func index(before index: Int) -> Int { index - 1 }
    public subscript(index: Int) -> QueryValue {
        precondition(indices.contains(index))
        return storage.value(at: storage.children[range.lowerBound + index])
    }
}
