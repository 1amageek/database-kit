import DatabaseTypes

/// Lowers model declarations into SQL expressions without evaluating a model.
enum PredicateExpression {
    static func lower<Model: Persistable>(_ predicate: Predicate<Model>) throws -> Expression {
        var nodes: UInt64 = 0
        return try lower(predicate, depth: 1, nodes: &nodes)
    }

    private static func lower<Model: Persistable>(
        _ predicate: Predicate<Model>, depth: UInt64, nodes: inout UInt64
    ) throws -> Expression {
        let limits = QueryStructuralLimits.default
        guard depth <= limits.maximumNestingDepth else {
            throw QueryStructuralValidationError.resourceLimitExceeded(resource: .nestingDepth,
                actual: depth, maximum: limits.maximumNestingDepth)
        }
        nodes += 1
        guard nodes <= limits.maximumTotalNodes else {
            throw QueryStructuralValidationError.resourceLimitExceeded(resource: .totalNodes,
                actual: nodes, maximum: limits.maximumTotalNodes)
        }
        switch predicate {
        case .true: return .literal(.bool(true))
        case .false: return .literal(.bool(false))
        case .not(let child): return .not(try lower(child, depth: depth + 1, nodes: &nodes))
        case .and(let children), .or(let children):
            guard UInt64(children.count) <= limits.maximumCollectionElements else {
                throw QueryStructuralValidationError.resourceLimitExceeded(resource: .collectionElements,
                    actual: UInt64(children.count), maximum: limits.maximumCollectionElements)
            }
            let conjunction: Bool
            if case .and = predicate { conjunction = true } else { conjunction = false }
            return try combine(children[...], conjunction: conjunction, depth: depth, nodes: &nodes)
        case .comparison(let comparison):
            guard comparison.field.number > 0,
                Model.fieldNumber(for: comparison.field.name) == comparison.field.number else {
                throw SelectionConstructionError.invalidFieldIdentity(comparison.field)
            }
            let column = Expression.column(ColumnRef(comparison.field.name))
            switch comparison.op {
            case .isNil: return .isNull(column)
            case .isNotNil: return .isNotNull(column)
            case .contains, .hasPrefix, .hasSuffix:
                throw SelectionConstructionError.unsupportedComparison(comparison.op)
            case .in, .notIn:
                guard case .array(let values) = comparison.value else {
                    throw SelectionConstructionError.invalidCollectionOperand
                }
                guard UInt64(values.count) <= limits.maximumCollectionElements else {
                    throw QueryStructuralValidationError.resourceLimitExceeded(resource: .collectionElements,
                        actual: UInt64(values.count), maximum: limits.maximumCollectionElements)
                }
                var items: [Expression] = []
                items.reserveCapacity(values.count)
                for value in values { items.append(try literal(value)) }
                return comparison.op == .in ? .inList(column, values: items) : .notInList(column, values: items)
            default:
                let value = try literal(comparison.value)
                switch comparison.op {
                case .equal: return .equal(column, value)
                case .notEqual: return .notEqual(column, value)
                case .lessThan: return .lessThan(column, value)
                case .lessThanOrEqual: return .lessThanOrEqual(column, value)
                case .greaterThan: return .greaterThan(column, value)
                case .greaterThanOrEqual: return .greaterThanOrEqual(column, value)
                default: throw SelectionConstructionError.unsupportedComparison(comparison.op)
                }
            }
        }
    }

    private static func combine<Model: Persistable>(
        _ children: ArraySlice<Predicate<Model>>, conjunction: Bool,
        depth: UInt64, nodes: inout UInt64
    ) throws -> Expression {
        guard !children.isEmpty else { return .literal(.bool(conjunction)) }
        if children.count == 1 {
            return try lower(children[children.startIndex], depth: depth + 1, nodes: &nodes)
        }
        let limits = QueryStructuralLimits.default
        guard depth < limits.maximumNestingDepth else {
            throw QueryStructuralValidationError.resourceLimitExceeded(resource: .nestingDepth,
                actual: depth + 1, maximum: limits.maximumNestingDepth)
        }
        nodes += 1
        guard nodes <= limits.maximumTotalNodes else {
            throw QueryStructuralValidationError.resourceLimitExceeded(resource: .totalNodes,
                actual: nodes, maximum: limits.maximumTotalNodes)
        }
        // Balanced association preserves leaf order without a linear-depth IR.
        let middle = children.startIndex + children.count / 2
        let left = try combine(children[..<middle], conjunction: conjunction, depth: depth + 1, nodes: &nodes)
        let right = try combine(children[middle...], conjunction: conjunction, depth: depth + 1, nodes: &nodes)
        return conjunction ? .and(left, right) : .or(left, right)
    }

    private static func literal(_ value: FieldValue) throws(SelectionConstructionError) -> Expression {
        switch value {
        case .array, .object: throw .invalidCollectionOperand
        default: return .literal(.queryValue(.primitive(value)))
        }
    }
}
