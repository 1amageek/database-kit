/// One statement or named checkpoint transition within an SQL block.
public enum SQLBlockStep: Sendable, Hashable {
    case statement(QueryStatement)
    case savepoint(String)
    case rollbackTo(String)
    case release(String)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
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
