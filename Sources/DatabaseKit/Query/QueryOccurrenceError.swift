/// A rejected semantic occurrence admission.
public enum QueryOccurrenceError: Error, Sendable, Equatable {
    case invalidParent(QueryOccurrenceID)
    case duplicateOccurrence
    case identifierOverflow
    case resourceLimit(QueryStructuralValidationError)
}
