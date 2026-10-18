/// Invokes a prepared definition using expressions in the caller's parameter scope.
public struct SQLExecute: Sendable, Hashable {
    public let name: String
    public let arguments: [Expression]
    public init(name: String, arguments: [Expression] = []) {
        self.name = name; self.arguments = arguments
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLDDLIdentity.equal(lhs.name, rhs.name) && lhs.arguments == rhs.arguments
    }
    public func hash(into hasher: inout Hasher) {
        SQLDDLIdentity.hash(name, into: &hasher); hasher.combine(arguments)
    }
}
