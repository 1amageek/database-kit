/// Aggregate effect of one atomic RDF dataset update.
///
/// Counts describe logical quads and explicit graph catalog entries.
/// Duplicate inserts and deletes of absent quads do not increment counts.
public struct RDFMutationEffect: Sendable, Hashable {
    public let insertedQuads: UInt64
    public let deletedQuads: UInt64
    public let createdGraphs: UInt64
    public let droppedGraphs: UInt64

    public init(
        insertedQuads: UInt64 = 0,
        deletedQuads: UInt64 = 0,
        createdGraphs: UInt64 = 0,
        droppedGraphs: UInt64 = 0
    ) {
        self.insertedQuads = insertedQuads
        self.deletedQuads = deletedQuads
        self.createdGraphs = createdGraphs
        self.droppedGraphs = droppedGraphs
    }
}
