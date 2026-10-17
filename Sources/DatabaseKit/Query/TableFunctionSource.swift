/// One implicitly lateral SQL FROM function invocation.
public struct TableFunctionSource: Sendable, Hashable {
    public let function: FunctionCall
    public let withOrdinality: Bool

    public init(function: FunctionCall, withOrdinality: Bool = false) {
        self.function = function
        self.withOrdinality = withOrdinality
    }
}
