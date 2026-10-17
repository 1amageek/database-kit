/// SQL window WindowReference declaration.
public enum WindowReference: Sendable, Hashable {
    case named(String)
    case specification(WindowSpecification)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        ExpressionIdentity.areEqual(.window(WindowCall(function: .analytic(.rowNumber, arguments: []), reference: lhs)), .window(WindowCall(function: .analytic(.rowNumber, arguments: []), reference: rhs)))
    }

    public func hash(into hasher: inout Hasher) {
        ExpressionIdentity.hash(.window(WindowCall(function: .analytic(.rowNumber, arguments: []), reference: self)), into: &hasher)
    }
}
