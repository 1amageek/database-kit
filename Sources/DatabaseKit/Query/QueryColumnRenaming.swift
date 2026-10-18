/// Renames exact column references within one expression's lexical scope.
public enum QueryColumnRenaming {
    /// Nested SELECT bodies retain their own lexical scope and are unchanged.
    public static func rename(_ expression: Expression, from: ColumnRef, to: ColumnRef,
        limits: QueryStructuralLimits = .default) throws(QueryParameterBindingError) -> Expression {
        do { try QueryStructuralValidator.validate(expression, limits: limits) }
        catch { throw .invalidStructure(error) }
        var traversal = QueryParameterBindingTraversal(positions: [:], names: [:], columnRenaming: (from, to))
        return try traversal.bindExpression(expression).value
    }
}
