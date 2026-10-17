/// SQL window WindowFrameExclusion declaration.
public enum WindowFrameExclusion: String, Sendable, Hashable {
    case noOthers
    case currentRow
    case group
    case ties
}
