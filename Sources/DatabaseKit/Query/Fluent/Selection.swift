/// A canonical query definition whose field APIs are restricted to one model.
public struct Selection<Model: Persistable>: Sendable {
    public let definition: SelectQuery

    public init(definition: SelectQuery) {
        self.definition = definition
    }

    public func select<each Value>(
        _ fields: repeat Field<Model, each Value>
    ) throws -> Self {
        var projection: [ProjectionItem] = []
        repeat projection.append(try projectionItem((each fields).identity))
        return Self(definition: definition.replacing(projection: projection.isEmpty ? [.wildcard()] : projection))
    }

    public func `where`(_ predicate: Predicate<Model>) throws -> Self {
        let expression = try PredicateExpression.lower(predicate)
        let query = definition.where(expression)
        try QueryStructuralValidator.validate(query)
        return Self(definition: query)
    }

    public func orderBy<Value>(
        _ field: Field<Model, Value>, _ direction: SortDirection = .ascending
    ) throws -> Self {
        try validate(field.identity)
        return Self(definition: definition.orderBy(.column(ColumnRef(field.name)), direction))
    }

    public func limit(_ count: UInt64) -> Self {
        Self(definition: definition.limit(count))
    }

    public func offset(_ count: UInt64) -> Self {
        Self(definition: definition.offset(count))
    }

    fileprivate func projectionItem(_ field: FieldIdentity) throws -> ProjectionItem {
        try validate(field)
        return ProjectionItem(.column(ColumnRef(field.name)))
    }

    private func validate(_ field: FieldIdentity) throws(SelectionConstructionError) {
        guard field.number > 0, Model.fieldNumber(for: field.name) == field.number else {
            throw .invalidFieldIdentity(field)
        }
    }
}

public extension Persistable {
    static func select<each Value>(
        _ fields: repeat Field<Self, each Value>
    ) throws -> Selection<Self> {
        let selection = Selection<Self>(definition: TableRef(persistableType).selectAll())
        var projection: [ProjectionItem] = []
        repeat projection.append(try selection.projectionItem((each fields).identity))
        return Selection<Self>(definition: selection.definition.replacing(
            projection: projection.isEmpty ? [.wildcard()] : projection))
    }
}
