/// Immutable SQL WindowFrame declaration; execution is owned by the SQL runtime.
public struct WindowFrame: Sendable, Hashable {
    public let mode: WindowFrameMode
    public let start: WindowFrameBound
    public let end: WindowFrameBound
    public let exclusion: WindowFrameExclusion

    public init(mode: WindowFrameMode, start: WindowFrameBound, end: WindowFrameBound, exclusion: WindowFrameExclusion = .noOthers) {
        self.mode = mode
        self.start = start
        self.end = end
        self.exclusion = exclusion
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        ExpressionIdentity.areEqual(.window(WindowCall(function: .analytic(.rowNumber, arguments: []), reference: .specification(WindowSpecification(frame: lhs)))), .window(WindowCall(function: .analytic(.rowNumber, arguments: []), reference: .specification(WindowSpecification(frame: rhs)))))
    }

    public func hash(into hasher: inout Hasher) {
        ExpressionIdentity.hash(.window(WindowCall(function: .analytic(.rowNumber, arguments: []), reference: .specification(WindowSpecification(frame: self)))), into: &hasher)
    }
}
