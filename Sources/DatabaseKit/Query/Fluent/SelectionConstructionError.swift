/// A typed query definition that cannot preserve the requested meaning.
public enum SelectionConstructionError: Error, Sendable, Equatable {
    case invalidFieldIdentity(FieldIdentity)
    case unsupportedComparison(FieldComparisonOperator)
    case invalidCollectionOperand
    case paginationOverflow(pageIndex: UInt64, pageSize: UInt64)
}
