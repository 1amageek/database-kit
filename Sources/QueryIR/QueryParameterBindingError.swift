public enum QueryParameterBindingError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidPosition(UInt32)
    case duplicatePosition(UInt32)
    case duplicateName(String)
    case missingPosition(UInt32)
    case missingName(String)
    case unsupportedValue(QueryParameterReference)

    public var description: String {
        switch self {
        case .invalidPosition(let position):
            return "Parameter position \(position) must be one-based"
        case .duplicatePosition(let position):
            return "Parameter position \(position) is duplicated"
        case .duplicateName(let name):
            return "Parameter name '\(name)' is duplicated"
        case .missingPosition(let position):
            return "Parameter position \(position) is not bound"
        case .missingName(let name):
            return "Parameter name '\(name)' is not bound"
        case .unsupportedValue(let reference):
            return "Parameter \(reference) cannot be represented by this QueryIR expression"
        }
    }
}
