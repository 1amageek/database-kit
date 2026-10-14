public struct QueryArrayDimension: Sendable, Hashable {
    public let lowerBound: Int32
    public let length: Int32

    public init(lowerBound: Int32, length: Int32) throws(QueryValueError) {
        guard length > 0,
              !lowerBound.addingReportingOverflow(length - 1).overflow else {
            throw .invalidDimension(lowerBound: lowerBound, length: length)
        }
        self.lowerBound = lowerBound
        self.length = length
    }
}
