/// A retained RDF result whose retrieval is owned by its runtime.
public protocol QueryGraph: AsyncSequence, Sendable where Element == RDFQuad {}
