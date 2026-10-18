/// The observable command completed by an SQL statement or checkpoint step.
public enum SQLCommandKind: Sendable, Hashable {
    case begin, commit, rollback, set, show, reset, prepare, execute, deallocate, explain, copy
    case createSchema
    case alterSchema
    case dropSchema
    case createTable
    case alterTable
    case dropTable
    case createIndex
    case dropIndex
    case createView
    case dropView
    case createMaterializedView
    case refreshMaterializedView
    case dropMaterializedView
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
        case .insert, .update, .delete, .merge, .copy: return true
        case .begin, .commit, .rollback, .set, .show, .reset, .prepare, .execute, .deallocate, .explain, .createSchema, .alterSchema, .dropSchema, .createTable, .alterTable, .dropTable, .createIndex, .dropIndex, .createView, .dropView, .createMaterializedView, .refreshMaterializedView, .dropMaterializedView, .truncate, .savepoint, .rollbackTo, .release, .setConstraints, .createSequence, .alterSequence, .dropSequence: return false
        }
    }
}
