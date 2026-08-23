/// Immutable candidate reranking input for a canonical Fusion plan.
public struct Rank<Item: Persistable>: FusionQueryInput, Sendable {
    public enum Order: Sendable {
        case ascending
        case descending
    }

    private let field: FieldIdentity
    private var sortOrder: Order = .descending

    public init<Value: IndexNumericValue>(_ field: Field<Item, Value>) {
        self.field = field.identity
    }

    public init<Value: IndexNumericValue>(_ field: Field<Item, Value?>) {
        self.field = field.identity
    }

    public func order(_ order: Order) -> Self {
        var copy = self
        copy.sortOrder = order
        return copy
    }

    public var fusionInput: FusionInput {
        let direction: SortDirection = switch sortOrder {
        case .ascending: .ascending
        case .descending: .descending
        }
        return FusionInput(
            operation: .order([
                SortKey(.col(field.name), direction: direction),
                SortKey(.col("id"), direction: .ascending),
            ]),
            scoring: .position,
            requirement: .candidates
        )
    }
}
