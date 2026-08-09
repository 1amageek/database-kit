/// A value returned through a Composition together with its complete origin.
public struct CompositionResult<Value: Sendable>: Sendable {
    public typealias Origin = CompositionOrigin

    public let compositionID: Base.Composition.ID
    public let generation: UInt64
    public let origin: Origin
    public let value: Value

    public init(
        compositionID: Base.Composition.ID,
        generation: UInt64,
        origin: Origin,
        value: consuming Value
    ) {
        self.compositionID = compositionID
        self.generation = generation
        self.origin = origin
        self.value = value
    }
}

extension CompositionResult: Equatable where Value: Equatable {}
extension CompositionResult: Hashable where Value: Hashable {}
