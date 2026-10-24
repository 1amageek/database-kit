import DatabaseKit

/// Iterates a retained page without changing the synchronous decoding API.
public struct QueryRowAsyncIterator: AsyncIteratorProtocol {
    private var iterator: QueryRowIterator

    init(_ iterator: QueryRowIterator) { self.iterator = iterator }

    public mutating func next() async throws(DatabaseWireError) -> QueryRow? {
        try iterator.next()
    }
}
