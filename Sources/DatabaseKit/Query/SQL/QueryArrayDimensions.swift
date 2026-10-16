public struct QueryArrayDimensions: Sendable, RandomAccessCollection {
    public typealias Index = Int
    public typealias Element = QueryArrayDimension
    let storage: QueryValueStorage
    let range: Range<Int>

    public var startIndex: Int { 0 }
    public var endIndex: Int { range.count }
    public func index(after index: Int) -> Int { index + 1 }
    public func index(before index: Int) -> Int { index - 1 }
    public subscript(index: Int) -> QueryArrayDimension {
        precondition(indices.contains(index))
        return storage.dimensions[range.lowerBound + index]
    }
}
