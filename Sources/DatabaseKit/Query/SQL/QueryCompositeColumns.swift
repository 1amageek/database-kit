public struct QueryCompositeColumns: Sendable, RandomAccessCollection {
    public typealias Index = Int
    public typealias Element = QueryColumn
    let storage: QueryTypeStorage
    let range: Range<Int>

    public var startIndex: Int { 0 }
    public var endIndex: Int { range.count }
    public func index(after index: Int) -> Int { index + 1 }
    public func index(before index: Int) -> Int { index - 1 }
    public subscript(index: Int) -> QueryColumn {
        precondition(indices.contains(index))
        let field = storage.columns[range.lowerBound + index]
        return QueryColumn(validatedNumber: field.number, name: field.name,
                           type: storage.type(at: field.type), isNullable: field.isNullable)
    }
}
