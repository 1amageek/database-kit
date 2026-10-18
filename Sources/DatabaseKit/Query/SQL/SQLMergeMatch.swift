/// The candidate class established before MERGE action selection.
public enum SQLMergeMatch: Sendable, Equatable, Hashable {
    case matched
    case notMatchedByTarget
    case notMatchedBySource
}
