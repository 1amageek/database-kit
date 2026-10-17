/// Immutable SQL WindowSpecification declaration; execution is owned by the SQL runtime.
public struct WindowSpecification: Sendable, Hashable {
    public let inheritedName: String?
    public let partitionBy: [Expression]
    public let orderBy: [SortKey]
    public let frame: WindowFrame?

    public init(inheritedName: String? = nil, partitionBy: [Expression] = [], orderBy: [SortKey] = [], frame: WindowFrame? = nil) {
        self.inheritedName = inheritedName
        self.partitionBy = partitionBy
        self.orderBy = orderBy
        self.frame = frame
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        ExpressionIdentity.areEqual(.window(WindowCall(function: .analytic(.rowNumber, arguments: []), reference: .specification(lhs))), .window(WindowCall(function: .analytic(.rowNumber, arguments: []), reference: .specification(rhs))))
    }

    public func hash(into hasher: inout Hasher) {
        ExpressionIdentity.hash(.window(WindowCall(function: .analytic(.rowNumber, arguments: []), reference: .specification(self))), into: &hasher)
    }
}
