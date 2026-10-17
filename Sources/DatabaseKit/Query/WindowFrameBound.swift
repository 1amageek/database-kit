/// SQL window WindowFrameBound declaration.
public indirect enum WindowFrameBound: Sendable, Hashable {
    case unboundedPreceding
    case preceding(Expression)
    case currentRow
    case following(Expression)
    case unboundedFollowing
}
