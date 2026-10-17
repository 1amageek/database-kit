/// The observable command completed by an SQL statement or checkpoint step.
public enum SQLCommandKind: Sendable, Hashable {
    case insert
    case update
    case delete
    case savepoint
    case rollbackTo
    case release

    /// Mutation commands report an affected-row count; checkpoint commands do not.
    public var reportsAffectedRows: Bool {
        switch self {
        case .insert, .update, .delete: return true
        case .savepoint, .rollbackTo, .release: return false
        }
    }
}
