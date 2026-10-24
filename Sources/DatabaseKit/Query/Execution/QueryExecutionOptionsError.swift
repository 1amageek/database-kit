/// An invalid query execution preference.
public enum QueryExecutionOptionsError: Error, Sendable, Equatable {
    case pageSizeMustBePositive
}
