/// SQL ANY or ALL reduction over examined scalar comparisons.
public enum ComparisonQuantifier: Sendable, Equatable, Hashable {
    case any
    case all
}
