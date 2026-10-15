/// One node's parent edge in a source-independent semantic occurrence arena.
public struct QueryOccurrence: Sendable, Equatable, Hashable {
    public let parent: QueryOccurrenceID?
    public let field: QueryOccurrenceField
    public let index: UInt32?
    public let depth: UInt64
}
