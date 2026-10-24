/// A Boolean result that may carry additional runtime-independent provenance.
public protocol QueryBoolean: Sendable {
    var value: Bool { get }
}

extension Bool: QueryBoolean {
    public var value: Bool { self }
}
