extension QueryStructuralValidator {
    private struct IdentifierIdentity: Hashable {
        let value: String

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.value.utf8.elementsEqual(rhs.value.utf8)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(value.utf8.count)
            for byte in value.utf8 { hasher.combine(byte) }
        }
    }

    private static func hasUniqueKeys(_ columns: [String]) -> Bool {
        guard !columns.isEmpty else { return false }
        var names: Set<IdentifierIdentity> = []
        for column in columns {
            guard !column.isEmpty, names.insert(IdentifierIdentity(value: column)).inserted else { return false }
        }
        return true
    }

    private static func contains(_ columns: [String], _ name: String) -> Bool {
        columns.contains { $0.utf8.elementsEqual(name.utf8) }
    }

    /// Shape checks are shared with Wire; the enclosing graph owns resource admission.
    package static func validate(_ search: CTESearchClause) throws(QueryStructuralValidationError) {
        guard hasUniqueKeys(search.columns), !search.sequenceColumn.isEmpty,
              !contains(search.columns, search.sequenceColumn) else { throw .invalidCTESearchClause }
    }

    package static func validate(_ cycle: CTECycleClause) throws(QueryStructuralValidationError) {
        guard hasUniqueKeys(cycle.columns), !cycle.markColumn.isEmpty, !cycle.pathColumn.isEmpty,
              !cycle.markColumn.utf8.elementsEqual(cycle.pathColumn.utf8),
              !contains(cycle.columns, cycle.markColumn), !contains(cycle.columns, cycle.pathColumn),
              (cycle.markValue == nil) == (cycle.defaultValue == nil) else { throw .invalidCTECycleClause }
        for value in [cycle.markValue, cycle.defaultValue] {
            guard let value else { continue }
            switch value {
            case .null, .bool, .int, .uint, .decimal, .double, .string, .sqlUnknownString,
                 .date, .timestamp, .binary, .uuid, .queryValue:
                break
            case .array, .iri, .blankNode, .typedLiteral, .langLiteral, .dirLangLiteral, .rdfTerm:
                throw .invalidCTECycleClause
            }
        }
    }

    package static func validate(_ source: TableFunctionSource) throws(QueryStructuralValidationError) {
        let function = source.function
        guard !function.name.isEmpty, function.schema?.isEmpty != true, !function.distinct else {
            throw .invalidTableFunctionSource
        }
        guard !function.finalArrayIsVariadic || !function.arguments.isEmpty else {
            throw .emptyVariadicFunctionArguments
        }
    }

    package static func validate(_ subquery: NamedSubquery) throws(QueryStructuralValidationError) {
        try validateCTEMetadata(columns: subquery.columns, search: subquery.search, cycle: subquery.cycle)
    }

    package static func validate(_ statement: SQLNamedStatement) throws(QueryStructuralValidationError) {
        try validateCTEMetadata(columns: statement.columns, search: statement.search, cycle: statement.cycle)
    }

    private static func validateCTEMetadata(columns: [String]?, search: CTESearchClause?, cycle: CTECycleClause?) throws(QueryStructuralValidationError) {
        if let search = search {
            try validate(search)
            guard !contains(columns ?? [], search.sequenceColumn),
                  !contains(cycle?.columns ?? [], search.sequenceColumn) else { throw .invalidCTESearchClause }
        }
        if let cycle = cycle {
            try validate(cycle)
            let declaredColumns = columns ?? []
            let searchKeys = search?.columns ?? []
            guard !contains(declaredColumns, cycle.markColumn), !contains(declaredColumns, cycle.pathColumn),
                  !contains(searchKeys, cycle.markColumn), !contains(searchKeys, cycle.pathColumn) else { throw .invalidCTECycleClause }
            if let sequence = search?.sequenceColumn {
                guard !sequence.utf8.elementsEqual(cycle.markColumn.utf8),
                      !sequence.utf8.elementsEqual(cycle.pathColumn.utf8) else { throw .invalidCTECycleClause }
            }
        }
    }
}
