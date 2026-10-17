/// Immutable SQL WindowCall declaration; execution is owned by the SQL runtime.
public struct WindowCall: Sendable, Hashable {
    public let function: WindowFunction
    public let reference: WindowReference

    public init(function: WindowFunction, reference: WindowReference) {
        self.function = function
        self.reference = reference
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        ExpressionIdentity.areEqual(.window(lhs), .window(rhs))
    }

    public func hash(into hasher: inout Hasher) {
        ExpressionIdentity.hash(.window(self), into: &hasher)
    }
}
