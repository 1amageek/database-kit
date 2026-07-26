/// Invalid resource limits supplied to the RDF wire representation.
enum RDFTermWireLimitsError: Error, Sendable, Equatable {
    case negativeMaximumBytes(Int)
    case negativeMaximumDepth(Int)
    case nonPositiveMaximumObjectCount(Int)
}
