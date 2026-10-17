/// The physical or virtual source of one SQL column.
public enum SQLColumnBacking: Sendable, Hashable {
    case field(number: Int)
    case virtual(type: QueryColumnType)
}
