/// A non-empty, ordered SPARQL Update request.
///
/// The first operation is stored separately so an empty request cannot be
/// represented. Iteration reads the two backing fields without materializing
/// an intermediate operation array.
public struct SPARQLUpdateRequest: Sendable, Equatable, Hashable, RandomAccessCollection {
    public typealias Element = SPARQLUpdateOperation
    public typealias Index = Int

    public let firstOperation: SPARQLUpdateOperation
    public let additionalOperations: [SPARQLUpdateOperation]

    public init(
        firstOperation: consuming SPARQLUpdateOperation,
        additionalOperations: consuming [SPARQLUpdateOperation] = []
    ) {
        self.firstOperation = consume firstOperation
        self.additionalOperations = consume additionalOperations
    }

    public var startIndex: Int { 0 }

    public var endIndex: Int { additionalOperations.count + 1 }

    public subscript(position: Int) -> SPARQLUpdateOperation {
        precondition(position >= startIndex && position < endIndex)
        if position == 0 {
            return firstOperation
        }
        return additionalOperations[position - 1]
    }

    public func index(after index: Int) -> Int {
        index + 1
    }

    public func index(before index: Int) -> Int {
        index - 1
    }
}
