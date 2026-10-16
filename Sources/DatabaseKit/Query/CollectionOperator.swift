/// Closed SQL collection operators; operand semantics are selected by binding.
public enum CollectionOperator: UInt8, Sendable, Hashable {
    case contains = 0
    case containedBy = 1
    case overlaps = 2
    case jsonField = 3
    case jsonFieldText = 4
    case jsonPath = 5
    case jsonPathText = 6
    case jsonHasKey = 7
    case jsonHasAnyKey = 8
    case jsonHasAllKeys = 9
    case jsonDeletePath = 10
}
