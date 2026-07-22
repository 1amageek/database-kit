public enum DatabaseRDFPredicateIRIError: Error, Sendable, Equatable {
    case invalidIRI(DatabaseRDFIRIError)
}
