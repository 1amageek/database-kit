/// One ordered syntax element in a SPARQL basic graph pattern.
public enum BasicGraphPatternElement: Sendable, Equatable, Hashable {
    case triple(TriplePattern)
    case propertyPath(SPARQLPropertyPathPattern)
}
