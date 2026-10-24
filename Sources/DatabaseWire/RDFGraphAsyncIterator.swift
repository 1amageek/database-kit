import DatabaseKit

/// Iterates retained graph values without copying the complete page.
public struct RDFGraphAsyncIterator: AsyncIteratorProtocol {
    private var iterator: RDFQuadIterator

    init(_ iterator: RDFQuadIterator) { self.iterator = iterator }

    public mutating func next() async throws(DatabaseWireError) -> RDFQuad? {
        try iterator.next()
    }
}
