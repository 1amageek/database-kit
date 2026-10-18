/// Closed SQL declaration alternatives before catalog resolution.
public enum SQLDDLStatement: Sendable, Hashable {
    case createSchema(name: String, ifNotExists: Bool)
    case renameSchema(name: String, to: String)
    case dropSchema(names: [String], ifExists: Bool, behavior: SQLDropBehavior)
    case createTable(SQLCreateTable)
    case alterTable(SQLAlterTable)
    case dropTable(names: [TableRef], ifExists: Bool, behavior: SQLDropBehavior)
    case createIndex(SQLCreateIndex)
    case dropIndex(names: [TableRef], ifExists: Bool, behavior: SQLDropBehavior)
    case createView(SQLCreateView)
    case dropView(names: [TableRef], ifExists: Bool, behavior: SQLDropBehavior)
    case createMaterializedView(SQLCreateMaterializedView)
    case refreshMaterializedView(name: TableRef, withData: Bool)
    case dropMaterializedView(names: [TableRef], ifExists: Bool, behavior: SQLDropBehavior)
    case createSequence(SQLCreateSequence)
    case alterSequence(SQLAlterSequence)
    case dropSequence(names: [TableRef], ifExists: Bool, behavior: SQLDropBehavior)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.createSchema(let l0, let l1), .createSchema(let r0, let r1)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1)
        case (.renameSchema(let l0, let l1), .renameSchema(let r0, let r1)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1)
        case (.dropSchema(let l0, let l1, let l2), .dropSchema(let r0, let r1, let r2)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1) && SQLDDLIdentity.equal(l2, r2)
        case (.createTable(let l0), .createTable(let r0)): return SQLDDLIdentity.equal(l0, r0)
        case (.alterTable(let l0), .alterTable(let r0)): return SQLDDLIdentity.equal(l0, r0)
        case (.dropTable(let l0, let l1, let l2), .dropTable(let r0, let r1, let r2)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1) && SQLDDLIdentity.equal(l2, r2)
        case (.createIndex(let l0), .createIndex(let r0)): return SQLDDLIdentity.equal(l0, r0)
        case (.dropIndex(let l0, let l1, let l2), .dropIndex(let r0, let r1, let r2)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1) && SQLDDLIdentity.equal(l2, r2)
        case (.createView(let l0), .createView(let r0)): return SQLDDLIdentity.equal(l0, r0)
        case (.dropView(let l0, let l1, let l2), .dropView(let r0, let r1, let r2)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1) && SQLDDLIdentity.equal(l2, r2)
        case (.createMaterializedView(let l0), .createMaterializedView(let r0)): return SQLDDLIdentity.equal(l0, r0)
        case (.refreshMaterializedView(let l0, let l1), .refreshMaterializedView(let r0, let r1)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1)
        case (.dropMaterializedView(let l0, let l1, let l2), .dropMaterializedView(let r0, let r1, let r2)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1) && SQLDDLIdentity.equal(l2, r2)
        case (.createSequence(let l0), .createSequence(let r0)): return SQLDDLIdentity.equal(l0, r0)
        case (.alterSequence(let l0), .alterSequence(let r0)): return SQLDDLIdentity.equal(l0, r0)
        case (.dropSequence(let l0, let l1, let l2), .dropSequence(let r0, let r1, let r2)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1) && SQLDDLIdentity.equal(l2, r2)
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .createSchema(let v0, let v1):
            hasher.combine(0)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
        case .renameSchema(let v0, let v1):
            hasher.combine(1)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
        case .dropSchema(let v0, let v1, let v2):
            hasher.combine(2)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
            SQLDDLIdentity.hash(v2, into: &hasher)
        case .createTable(let v0):
            hasher.combine(3)
            SQLDDLIdentity.hash(v0, into: &hasher)
        case .alterTable(let v0):
            hasher.combine(4)
            SQLDDLIdentity.hash(v0, into: &hasher)
        case .dropTable(let v0, let v1, let v2):
            hasher.combine(5)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
            SQLDDLIdentity.hash(v2, into: &hasher)
        case .createIndex(let v0):
            hasher.combine(6)
            SQLDDLIdentity.hash(v0, into: &hasher)
        case .dropIndex(let v0, let v1, let v2):
            hasher.combine(7)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
            SQLDDLIdentity.hash(v2, into: &hasher)
        case .createView(let v0):
            hasher.combine(8)
            SQLDDLIdentity.hash(v0, into: &hasher)
        case .dropView(let v0, let v1, let v2):
            hasher.combine(9)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
            SQLDDLIdentity.hash(v2, into: &hasher)
        case .createMaterializedView(let v0):
            hasher.combine(10)
            SQLDDLIdentity.hash(v0, into: &hasher)
        case .refreshMaterializedView(let v0, let v1):
            hasher.combine(11)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
        case .dropMaterializedView(let v0, let v1, let v2):
            hasher.combine(12)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
            SQLDDLIdentity.hash(v2, into: &hasher)
        case .createSequence(let v0):
            hasher.combine(13)
            SQLDDLIdentity.hash(v0, into: &hasher)
        case .alterSequence(let v0):
            hasher.combine(14)
            SQLDDLIdentity.hash(v0, into: &hasher)
        case .dropSequence(let v0, let v1, let v2):
            hasher.combine(15)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
            SQLDDLIdentity.hash(v2, into: &hasher)
        }
    }
}

extension SQLDDLStatement {
    public var command: SQLCommandKind {
        switch self {
        case .createSchema: return .createSchema
        case .renameSchema: return .alterSchema
        case .dropSchema: return .dropSchema
        case .createTable: return .createTable
        case .alterTable: return .alterTable
        case .dropTable: return .dropTable
        case .createIndex: return .createIndex
        case .dropIndex: return .dropIndex
        case .createView: return .createView
        case .dropView: return .dropView
        case .createMaterializedView: return .createMaterializedView
        case .refreshMaterializedView: return .refreshMaterializedView
        case .dropMaterializedView: return .dropMaterializedView
        case .createSequence: return .createSequence
        case .alterSequence: return .alterSequence
        case .dropSequence: return .dropSequence
        }
    }
}
