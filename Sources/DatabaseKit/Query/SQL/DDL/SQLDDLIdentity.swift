/// Exact identifier identity shared by immutable DDL declarations.
enum SQLDDLIdentity {
    static func equal<T: Equatable>(_ lhs: T, _ rhs: T) -> Bool { lhs == rhs }
    static func equal(_ lhs: String, _ rhs: String) -> Bool { lhs.utf8.elementsEqual(rhs.utf8) }
    static func equal(_ lhs: String?, _ rhs: String?) -> Bool { ExpressionIdentity.nameEqual(lhs, rhs) }
    static func equal(_ lhs: [String], _ rhs: [String]) -> Bool { ExpressionIdentity.namesEqual(lhs, rhs) }
    static func equal(_ lhs: [String]?, _ rhs: [String]?) -> Bool { ExpressionIdentity.namesEqual(lhs, rhs) }
    static func equal(_ lhs: TableRef, _ rhs: TableRef) -> Bool {
        equal(lhs.schema, rhs.schema) && equal(lhs.table, rhs.table)
            && equal(lhs.alias, rhs.alias) && lhs.partitions == rhs.partitions
    }
    static func equal(_ lhs: [TableRef], _ rhs: [TableRef]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for index in lhs.indices where !equal(lhs[index], rhs[index]) { return false }
        return true
    }
    static func hash<T: Hashable>(_ value: T, into hasher: inout Hasher) { hasher.combine(value) }
    static func hash(_ value: String, into hasher: inout Hasher) { ExpressionIdentity.hashName(value, into: &hasher) }
    static func hash(_ value: String?, into hasher: inout Hasher) { ExpressionIdentity.hashName(value, into: &hasher) }
    static func hash(_ value: [String], into hasher: inout Hasher) { ExpressionIdentity.hashNames(value, into: &hasher) }
    static func hash(_ value: [String]?, into hasher: inout Hasher) { ExpressionIdentity.hashNames(value, into: &hasher) }
    static func hash(_ value: TableRef, into hasher: inout Hasher) {
        hash(value.schema, into: &hasher); hash(value.table, into: &hasher)
        hash(value.alias, into: &hasher); hasher.combine(value.partitions)
    }
    static func hash(_ values: [TableRef], into hasher: inout Hasher) {
        hasher.combine(values.count)
        for value in values { hash(value, into: &hasher) }
    }
}
