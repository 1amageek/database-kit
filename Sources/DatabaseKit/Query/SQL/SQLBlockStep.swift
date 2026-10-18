/// One ordinary statement, operational command or named checkpoint transition.
public enum SQLBlockStep: Sendable, Hashable {
    case transaction(SQLTransactionControl)
    case setting(SQLSettingCommand)
    case prepare(SQLPrepare)
    case execute(SQLExecute)
    case deallocate(String?)
    case explain(SQLExplain)
    case copy(SQLCopyCommand)
    case statement(QueryStatement)
    case setConstraints(SQLSetConstraints)
    case sequence(SQLSequenceCommand)
    case savepoint(String)
    case rollbackTo(String)
    case release(String)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.transaction(let l), .transaction(let r)): return l == r
        case (.setting(let l), .setting(let r)): return l == r
        case (.prepare(let l), .prepare(let r)): return l == r
        case (.execute(let l), .execute(let r)): return l == r
        case (.deallocate(let l), .deallocate(let r)): return SQLDDLIdentity.equal(l, r)
        case (.explain(let l), .explain(let r)): return l == r
        case (.copy(let l), .copy(let r)): return l == r
        case (.setConstraints(let left), .setConstraints(let right)): return left == right
        case (.sequence(let left), .sequence(let right)): return left == right
        case (.statement(let left), .statement(let right)):
            return left == right
        case (.savepoint(let left), .savepoint(let right)),
             (.rollbackTo(let left), .rollbackTo(let right)),
             (.release(let left), .release(let right)):
            return left.utf8.elementsEqual(right.utf8)
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        let name: String
        switch self {
        case .transaction(let value): hasher.combine(6); hasher.combine(value); return
        case .setting(let value): hasher.combine(7); hasher.combine(value); return
        case .prepare(let value): hasher.combine(8); hasher.combine(value); return
        case .execute(let value): hasher.combine(9); hasher.combine(value); return
        case .deallocate(let value): hasher.combine(10); SQLDDLIdentity.hash(value, into: &hasher); return
        case .explain(let value): hasher.combine(11); hasher.combine(value); return
        case .copy(let value): hasher.combine(12); hasher.combine(value); return
        case .setConstraints(let control): hasher.combine(4); hasher.combine(control); return
        case .sequence(let command): hasher.combine(5); hasher.combine(command); return
        case .statement(let statement):
            hasher.combine(0)
            hasher.combine(statement)
            return
        case .savepoint(let value):
            hasher.combine(1)
            name = value
        case .rollbackTo(let value):
            hasher.combine(2)
            name = value
        case .release(let value):
            hasher.combine(3)
            name = value
        }
        hasher.combine(name.utf8.count)
        for byte in name.utf8 { hasher.combine(byte) }
    }
}
