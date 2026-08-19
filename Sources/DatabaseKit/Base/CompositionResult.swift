#if DATABASE_KIT_MULTI_BASE
/// A value returned through a Composition together with its complete origin.
public struct CompositionResult<Value: Sendable>: Sendable {
    public typealias Origin = CompositionOrigin

    public let composition: CompositionResolution
    public let origin: Origin
    public let value: Value

    public init(
        composition: CompositionResolution,
        origin: Origin,
        value: consuming Value
    ) {
        self.composition = composition
        self.origin = origin
        self.value = value
    }
}

extension CompositionResult: Equatable where Value: Equatable {}
extension CompositionResult: Hashable where Value: Hashable {}

#endif
