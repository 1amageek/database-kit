/// An interpolated SQL input exceeded its intrinsic parameter address space.
public enum SQLInterpolationError: Error, Sendable, Equatable {
    case tooManyParameters
}
