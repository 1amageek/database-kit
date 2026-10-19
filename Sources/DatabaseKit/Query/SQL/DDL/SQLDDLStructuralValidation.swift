/// Fixed-width scheduling nodes for DDL's bounded declaration traversal.
enum SQLDDLValidationStep {
    case statement(SQLDDLStatement)
    case definition(SQLTableDefinition)
    case column(SQLColumnDefinition)
    case constraint(SQLTableConstraint)
    case foreignKey(SQLForeignKeyDefinition)
    case action(SQLAlterTableAction)
    case options(SQLSequenceOptions)
    case ownership(SQLSequenceOwnership)
    case columns([SQLColumnDefinition], Int)
    case constraints([SQLTableConstraint], Int)
    case actions([SQLAlterTableAction], Int)
    case targets([TableRef], Int)
    case keys([SortKey], Int)
    case expression(Expression)
    case query(SelectQuery)
    case type(DataType)

    var isCursor: Bool {
        switch self {
        case .columns, .constraints, .actions, .targets, .keys: true
        default: false
        }
    }
}

/// Admits metadata before scheduling retained indexed children on the shared ledger.
enum SQLDDLStructuralValidation {
    static func schedule(_ step: SQLDDLValidationStep, ledger: inout QueryStructuralResourceLedger)
    throws(QueryStructuralValidationError) -> [SQLDDLValidationStep] {
        switch step {
        case .expression, .query, .type: return []
        case .columns(let values, let index):
            guard index < values.count else { return [] }
            return [.columns(values, index + 1), .column(values[index])]
        case .constraints(let values, let index):
            guard index < values.count else { return [] }
            return [.constraints(values, index + 1), .constraint(values[index])]
        case .actions(let values, let index):
            guard index < values.count else { return [] }
            return [.actions(values, index + 1), .action(values[index])]
        case .targets(let values, let index):
            guard index < values.count else { return [] }
            try target(values[index], ledger: &ledger)
            return [.targets(values, index + 1)]
        case .keys(let values, let index):
            guard index < values.count else { return [] }
            return [.keys(values, index + 1), .expression(values[index].expression)]
        case .definition(let value):
            switch value {
            case .columns(let columns, let constraints):
                try count(columns.count, ledger: &ledger)
                try count(constraints.count, ledger: &ledger)
                var names: Set<SQLIdentifier> = []
                for column in columns {
                    guard names.insert(SQLIdentifier(value: column.name)).inserted else { throw .invalidSQLDDL }
                }
                return [.constraints(constraints, 0), .columns(columns, 0)]
            case .query(let query, let columns, _):
                if let columns { try names(columns, ledger: &ledger) }
                return [.query(query)]
            }
        case .column(let column):
            try name(column.name, ledger: &ledger)
            try count(column.constraints.count, ledger: &ledger)
            for constraint in column.constraints {
                let local: [String]
                switch constraint.kind {
                case .primaryKey(let columns), .unique(let columns, _): local = columns
                case .notNull(let name): local = [name]
                case .foreignKey(let key): local = key.columns
                case .check: continue
                }
                guard local.count == 1, local[0].utf8.elementsEqual(column.name.utf8) else { throw .invalidSQLDDL }
            }
            var children: [SQLDDLValidationStep] = [.constraints(column.constraints, 0), .type(column.type)]
            switch column.policy {
            case .input(let expression): if let expression { children.append(.expression(expression)) }
            case .generated(let expression, _): children.append(.expression(expression))
            case .identity(_, let options):
                guard integral(column.type) else { throw .invalidSQLDDL }
                children.append(.options(options))
            case .serial: guard integral(column.type) else { throw .invalidSQLDDL }
            }
            return children
        case .constraint(let constraint):
            if let value = constraint.name { try name(value, ledger: &ledger) }
            switch constraint.kind {
            case .primaryKey(let columns), .unique(let columns, _):
                try names(columns, ledger: &ledger)
                return []
            case .notNull(let column):
                guard constraint.timing == .immediate else { throw .invalidSQLDDL }
                try name(column, ledger: &ledger)
                return []
            case .check(let expression):
                guard constraint.timing == .immediate else { throw .invalidSQLDDL }
                return [.expression(expression)]
            case .foreignKey(let key): return [.foreignKey(key)]
            }
        case .foreignKey(let key):
            try names(key.columns, ledger: &ledger)
            try target(key.referencedTable, ledger: &ledger)
            if let columns = key.referencedColumns {
                try names(columns, ledger: &ledger)
                guard columns.count == key.columns.count else { throw .invalidSQLDDL }
            }
            if let columns = key.onDeleteColumns {
                try names(columns, ledger: &ledger)
                guard key.onDelete == .setNull || key.onDelete == .setDefault else { throw .invalidSQLDDL }
                let source = Set(key.columns.map { SQLIdentifier(value: $0) })
                guard columns.allSatisfy({ source.contains(SQLIdentifier(value: $0)) }) else { throw .invalidSQLDDL }
            }
            return []
        case .options(let options):
            guard options.increment != 0 else { throw .invalidSQLSequenceOptions }
            if case .value(let minimum) = options.minimum, case .value(let maximum) = options.maximum,
               minimum >= maximum { throw .invalidSQLSequenceOptions }
            if let start = options.start {
                if case .value(let minimum) = options.minimum, start < minimum { throw .invalidSQLSequenceOptions }
                if case .value(let maximum) = options.maximum, start > maximum { throw .invalidSQLSequenceOptions }
            }
            if let type = options.type {
                guard integral(type) else { throw .invalidSQLSequenceOptions }
                return [.type(type)]
            }
            return []
        case .ownership(let owner):
            if case .column(let table, let column) = owner {
                try target(table, ledger: &ledger)
                try name(column, ledger: &ledger)
            }
            return []
        case .action(let action):
            switch action {
            case .addColumn(let column, _): return [.column(column)]
            case .dropColumn(let column, _, _), .dropDefault(let column), .setNotNull(let column), .dropNotNull(let column):
                try name(column, ledger: &ledger); return []
            case .renameColumn(let column, let replacement):
                try name(column, ledger: &ledger); try name(replacement, ledger: &ledger); return []
            case .alterColumnType(let column, let type, let expression):
                try name(column, ledger: &ledger)
                var children: [SQLDDLValidationStep] = [.type(type)]
                if let expression { children.append(.expression(expression)) }
                return children
            case .setDefault(let column, let expression):
                try name(column, ledger: &ledger); return [.expression(expression)]
            case .addConstraint(let constraint): return [.constraint(constraint)]
            case .dropConstraint(let constraint, _, _): try name(constraint, ledger: &ledger); return []
            case .renameTable(let replacement): try name(replacement, ledger: &ledger); return []
            }
        case .statement(let statement):
            switch statement {
            case .createSchema(let value, _): try name(value, ledger: &ledger); return []
            case .renameSchema(let value, let replacement):
                try name(value, ledger: &ledger); try name(replacement, ledger: &ledger); return []
            case .dropSchema(let values, _, _): try names(values, ledger: &ledger); return []
            case .createTable(let table):
                try target(table.name, ledger: &ledger); return [.definition(table.source)]
            case .alterTable(let table):
                try target(table.name, ledger: &ledger)
                guard !table.actions.isEmpty else { throw .invalidSQLDDL }
                try count(table.actions.count, ledger: &ledger)
                return [.actions(table.actions, 0)]
            case .dropTable(let targets, _, _), .dropIndex(let targets, _, _),
                 .dropView(let targets, _, _), .dropMaterializedView(let targets, _, _), .dropSequence(let targets, _, _):
                guard !targets.isEmpty else { throw .invalidSQLDDL }
                try count(targets.count, ledger: &ledger)
                return [.targets(targets, 0)]
            case .createIndex(let index):
                guard index.name.schema == nil else { throw .invalidSQLDDL }
                try target(index.name, ledger: &ledger); try target(index.table, ledger: &ledger)
                guard !index.keys.isEmpty, index.unique || index.nulls == .distinct else { throw .invalidSQLDDL }
                try count(index.keys.count, ledger: &ledger)
                var children: [SQLDDLValidationStep] = [.keys(index.keys, 0)]
                if let predicate = index.predicate { children.append(.expression(predicate)) }
                return children
            case .createView(let view):
                try target(view.name, ledger: &ledger)
                if let columns = view.columns { try names(columns, ledger: &ledger) }
                return [.query(view.query)]
            case .createMaterializedView(let view):
                try target(view.name, ledger: &ledger)
                if let columns = view.columns { try names(columns, ledger: &ledger) }
                return [.query(view.query)]
            case .refreshMaterializedView(let value, _): try target(value, ledger: &ledger); return []
            case .createSequence(let sequence):
                try target(sequence.name, ledger: &ledger)
                var children: [SQLDDLValidationStep] = [.options(sequence.options)]
                if let owner = sequence.ownedBy { children.append(.ownership(owner)) }
                return children
            case .alterSequence(let sequence):
                try target(sequence.name, ledger: &ledger)
                if let replacement = sequence.renameTo { try name(replacement, ledger: &ledger) }
                var children: [SQLDDLValidationStep] = [.options(sequence.options)]
                if let owner = sequence.ownedBy { children.append(.ownership(owner)) }
                return children
            }
        }
    }

    private static func name(_ value: String, ledger: inout QueryStructuralResourceLedger) throws(QueryStructuralValidationError) {
        guard !value.isEmpty, !value.utf8.contains(0) else { throw .invalidSQLDDL }
        try ledger.consume(.retainedBytes, amount: UInt64(value.utf8.count))
    }

    private static func names(_ values: [String], ledger: inout QueryStructuralResourceLedger) throws(QueryStructuralValidationError) {
        guard !values.isEmpty else { throw .invalidSQLDDL }
        try count(values.count, ledger: &ledger)
        var seen: Set<SQLIdentifier> = []
        for value in values {
            try name(value, ledger: &ledger)
            guard seen.insert(SQLIdentifier(value: value)).inserted else { throw .invalidSQLDDL }
        }
    }

    private static func count(_ value: Int, ledger: inout QueryStructuralResourceLedger) throws(QueryStructuralValidationError) {
        try ledger.consume(.collectionElements, amount: UInt64(value))
    }

    private static func target(_ table: TableRef, ledger: inout QueryStructuralResourceLedger) throws(QueryStructuralValidationError) {
        guard table.alias == nil, table.partitions.isEmpty else { throw .invalidSQLDDL }
        try name(table.table, ledger: &ledger)
        if let schema = table.schema { try name(schema, ledger: &ledger) }
    }

    private static func integral(_ type: DataType) -> Bool {
        switch type { case .smallint, .integer, .bigint: true; default: false }
    }
}
