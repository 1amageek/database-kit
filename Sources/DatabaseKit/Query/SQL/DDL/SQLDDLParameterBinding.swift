/// Reconstructs DDL's fixed declaration layers; recursive query children use the existing iterative traversal.
struct SQLDDLParameterBinding {
    let positions: [UInt32: QueryParameter]
    let names: [String: QueryParameter]
    private(set) var changed = false

    init(positions: [UInt32: QueryParameter], names: [String: QueryParameter]) {
        self.positions = positions
        self.names = names
    }

    mutating func bind(_ declaration: SQLDDLStatement) throws(QueryParameterBindingError) -> SQLDDLStatement {
        switch declaration {
        case .createTable(let table):
            return .createTable(SQLCreateTable(name: table.name, source: try definition(table.source), temporary: table.temporary, ifNotExists: table.ifNotExists))
        case .alterTable(let table):
            var actions: [SQLAlterTableAction] = []
            actions.reserveCapacity(table.actions.count)
            for value in table.actions { actions.append(try action(value)) }
            return .alterTable(SQLAlterTable(name: table.name, actions: actions, ifExists: table.ifExists))
        case .createIndex(let index):
            var keys: [SortKey] = []
            keys.reserveCapacity(index.keys.count)
            for key in index.keys { keys.append(SortKey(try expression(key.expression), direction: key.direction, nulls: key.nulls)) }
            return .createIndex(SQLCreateIndex(name: index.name, table: index.table, keys: keys,
                predicate: try optionalExpression(index.predicate), unique: index.unique, nulls: index.nulls, ifNotExists: index.ifNotExists))
        case .createView(let view):
            return .createView(SQLCreateView(name: view.name, columns: view.columns, query: try query(view.query), orReplace: view.orReplace))
        case .createMaterializedView(let view):
            return .createMaterializedView(SQLCreateMaterializedView(name: view.name, columns: view.columns,
                query: try query(view.query), withData: view.withData, ifNotExists: view.ifNotExists))
        default: return declaration
        }
    }

    private mutating func definition(_ value: SQLTableDefinition) throws(QueryParameterBindingError) -> SQLTableDefinition {
        switch value {
        case .columns(let columns, let constraints):
            var output: [SQLColumnDefinition] = []
            output.reserveCapacity(columns.count)
            for column in columns { output.append(try self.column(column)) }
            return .columns(output, constraints: try self.constraints(constraints))
        case .query(let value, let columns, let withData):
            return .query(try query(value), columns: columns, withData: withData)
        }
    }

    private mutating func column(_ value: SQLColumnDefinition) throws(QueryParameterBindingError) -> SQLColumnDefinition {
        let policy: SQLColumnDefinitionPolicy
        switch value.policy {
        case .input(let value): policy = .input(defaultExpression: try optionalExpression(value))
        case .generated(let value, let stored): policy = .generated(try expression(value), stored: stored)
        case .identity, .serial: policy = value.policy
        }
        return SQLColumnDefinition(name: value.name, type: value.type, policy: policy, constraints: try constraints(value.constraints))
    }

    private mutating func constraints(_ values: [SQLTableConstraint]) throws(QueryParameterBindingError) -> [SQLTableConstraint] {
        var output: [SQLTableConstraint] = []
        output.reserveCapacity(values.count)
        for value in values { output.append(try constraint(value)) }
        return output
    }

    private mutating func constraint(_ value: SQLTableConstraint) throws(QueryParameterBindingError) -> SQLTableConstraint {
        guard case .check(let check) = value.kind else { return value }
        return SQLTableConstraint(name: value.name, timing: value.timing, kind: .check(try expression(check)))
    }

    private mutating func action(_ value: SQLAlterTableAction) throws(QueryParameterBindingError) -> SQLAlterTableAction {
        switch value {
        case .addColumn(let value, let ifNotExists): return .addColumn(try column(value), ifNotExists: ifNotExists)
        case .alterColumnType(let name, let type, let using): return .alterColumnType(name: name, type: type, using: try optionalExpression(using))
        case .setDefault(let name, let value): return .setDefault(column: name, expression: try expression(value))
        case .addConstraint(let value): return .addConstraint(try constraint(value))
        default: return value
        }
    }

    private mutating func expression(_ value: Expression) throws(QueryParameterBindingError) -> Expression {
        var traversal = QueryParameterBindingTraversal(positions: positions, names: names)
        let result = try traversal.bindExpression(value)
        changed = changed || result.changed
        return result.value
    }

    private mutating func optionalExpression(_ value: Expression?) throws(QueryParameterBindingError) -> Expression? {
        guard let value else { return nil }
        return try expression(value)
    }

    private mutating func query(_ value: SelectQuery) throws(QueryParameterBindingError) -> SelectQuery {
        var traversal = QueryParameterBindingTraversal(positions: positions, names: names)
        guard case .select(let result) = try traversal.bind(.select(value)) else { throw .invalidTraversalState }
        changed = changed || result != value
        return result
    }
}
