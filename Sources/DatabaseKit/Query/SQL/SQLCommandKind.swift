/// The observable command completed by an SQL statement or checkpoint step.
public enum SQLCommandKind: Sendable, Hashable {
    case setConstraints
    case createSequence
    case alterSequence
    case dropSequence
    case insert
    case update
    case delete
    case merge
    case truncate
    case savepoint
    case rollbackTo
    case release

    /// Mutation commands report an affected-row count; checkpoint commands do not.
    public var reportsAffectedRows: Bool {
        switch self {
        case .insert, .update, .delete, .merge: return true
        case .truncate, .savepoint, .rollbackTo, .release, .setConstraints, .createSequence, .alterSequence, .dropSequence: return false
        }
    }
}
