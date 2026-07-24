/// Invalid resource limits supplied to the canonical RDF term codec.
public enum RDFTermCodecLimitsError: Error, Sendable, Equatable {
    case negativeMaximumBytes(Int)
    case negativeMaximumDepth(Int)
    case nonPositiveMaximumObjectCount(Int)
}
