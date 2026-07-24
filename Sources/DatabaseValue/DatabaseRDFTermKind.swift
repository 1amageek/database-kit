public enum RDFTermKind: UInt8, Sendable, Equatable {
    case blankNode = 1
    case iri = 2
    case literal = 3
    case tripleTerm = 4
}
