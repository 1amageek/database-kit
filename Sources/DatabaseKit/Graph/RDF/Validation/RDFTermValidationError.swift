public enum RDFTermValidationError: Error, Sendable, Equatable {
    case invalidRole(expected: RDFTermRole, actual: RDFTermKind)
    case termCountOverflow
    case maximumDepthExceeded(actual: Int, maximum: Int)
    case maximumTermCountExceeded(actual: Int, maximum: Int)
}
