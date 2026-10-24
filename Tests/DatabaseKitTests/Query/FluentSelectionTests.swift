import DatabaseKit
import DatabaseTypes
import Testing

@Suite("Canonical fluent selection")
struct FluentSelectionTests {
    @Test("Adapter metadata projection uses canonical validation and source construction")
    func adapterProjection() throws {
        let base = try FluentPerson.select()
        let identities = [FluentPerson.fields.name.identity, FluentPerson.fields.age.identity, FluentPerson.fields.name.identity]
        #expect(try base.select(fields: identities).definition == FluentPerson.select(FluentPerson.fields.name, FluentPerson.fields.age, FluentPerson.fields.name).definition)
        #expect(try base.select(fields: []).definition == base.definition)
        let forged = FieldIdentity(name: "name", number: 9999)
        #expect(throws: SelectionConstructionError.invalidFieldIdentity(forged)) { try base.select(fields: [forged]) }
        let table = TableRef(schema: "Exact", table: "items", alias: "i")
        #expect(table.select(columns: ["name", "name"]) == table.select("name", "name"))
        #expect(table.select(columns: []) == table.selectAll())
    }
    @Test("Heterogeneous typed projections preserve order and duplicates")
    func projections() throws {
        let query = try FluentPerson.select(#field(\FluentPerson.name), #field(\FluentPerson.age), #field(\FluentPerson.name))
        #expect(query.definition.projection == [ProjectionItem(.col("name")), ProjectionItem(.col("age")), ProjectionItem(.col("name"))])
        #expect(query.definition.source == .table(TableRef("FluentPerson")))
    }

    @Test("Typed comparison literals retain their declared integer width")
    func exactWidths() throws {
        let query = try FluentPerson.select().where(#field(\FluentPerson.age) > Int32(18))
        #expect(query.definition.filter == .greaterThan(.col("age"), .literal(.queryValue(.primitive(.int32(18))))))
    }

    @Test("Canonical SQL negation keeps NULL comparison semantics")
    func nullNegation() throws {
        let field = #field(\FluentPerson.nickname)
        let predicate = Predicate<FluentPerson>.not(.comparison(FieldComparison(field: field, op: .equal, value: FieldValue.null)))
        let query = try FluentPerson.select().where(predicate)
        #expect(query.definition.filter == .not(.equal(.col("nickname"), .literal(.queryValue(.primitive(.null))))))
    }

    @Test("Invalid compiled field identity fails before invocation")
    func invalidField() throws {
        let field = Field<FluentPerson, String>(identity: .init(name: "name", number: 9999), type: .string)
        #expect(throws: SelectionConstructionError.invalidFieldIdentity(field.identity)) {
            try FluentPerson.select(field)
        }
        #expect(throws: SelectionConstructionError.invalidFieldIdentity(field.identity)) {
            try FluentPerson.select().where(field == "value")
        }
    }

    @Test("Model-specific string operations are explicit unsupported failures")
    func unsupportedModelOperator() throws {
        #expect(throws: SelectionConstructionError.unsupportedComparison(.contains)) {
            try FluentPerson.select().where(.contains("a", in: #field(\FluentPerson.name)))
        }
    }

    @Test("Deep predicate input is rejected within canonical structural limits")
    func boundedLowering() throws {
        var predicate = Predicate<FluentPerson>.true
        for _ in 0..<65 { predicate = .not(predicate) }
        #expect(throws: QueryStructuralValidationError.self) { try FluentPerson.select().where(predicate) }
        let wide = try FluentPerson.select().where(.and(Array(repeating: .true, count: 128)))
        try QueryStructuralValidator.validate(wide.definition)
    }

    @Test("Source aliases, schema names and partitions survive construction")
    func sourceMetadata() throws {
        let partitions = try FieldObject([("region", .string("east"))])
        let table = TableRef(schema: "Mixed Schema", table: "events.name", alias: "e", partitions: partitions)
        let query = table.select("name").limit(20).offset(7)
        #expect(query.source == .aliased(.table(TableRef(schema: table.schema, table: table.table, partitions: partitions)), name: "e"))
        try QueryStructuralValidator.validate(query)
    }

    @Test("Immutable branches retain filters and ordered sort keys independently")
    func branches() throws {
        let base = try FluentPerson.select().where(#field(\FluentPerson.isActive) == true)
        let ordered = try base.orderBy(#field(\FluentPerson.name)).orderBy(#field(\FluentPerson.age), .descending)
        #expect(base.definition.orderBy == nil)
        #expect(ordered.definition.filter == base.definition.filter)
        #expect(ordered.definition.orderBy == [SortKey(.col("name")), SortKey(.col("age"), direction: .descending)])
        #expect(base.limit(2).definition.pagination.limit == .count(.fixed(2), withTies: false))
        #expect(base.definition.pagination.limit == nil)
    }

    @Test("Named predicates compose with AND and OR without changing precedence")
    func booleanComposition() {
        let a = Expression.equal(.col("age"), .int(18))
        let b = Expression.equal(.col("name"), .string("one"))
        let c = Expression.isNull(.col("nickname"))
        let query = TableRef("users").selectAll().where(a).where(b).orWhere(c)
        #expect(query.filter == .or(.and(a, b), c))
    }

    @Test("Pagination preserves zero counts and fails on multiplication overflow")
    func pagination() throws {
        let query = TableRef("users").selectAll()
        #expect(try query.paginate(pageIndex: 3, pageSize: 20).pagination.offset == .fixed(60))
        #expect(query.limit(0).pagination.limit == .count(.fixed(0), withTies: false))
        #expect(throws: SelectionConstructionError.paginationOverflow(pageIndex: .max, pageSize: 2)) {
            try query.paginate(pageIndex: .max, pageSize: 2)
        }
    }

    @Test("Fluent changes preserve unrelated query envelope clauses")
    func envelope() throws {
        let inner = TableRef("items").select("id")
        let original = SelectQuery(projection: [.wildcard()], source: .table(TableRef("items")),
            groupBy: [.expression(.col("id"))], having: .literal(.bool(true)),
            quantifier: .distinct, subqueries: [NamedSubquery(name: "cte", query: inner)], withRecursive: true)
        let changed = original.limit(4).where(.literal(.bool(true))).orderBy("id")
        #expect(changed.groupBy == original.groupBy)
        #expect(changed.having == original.having)
        #expect(changed.quantifier == original.quantifier)
        #expect(changed.subqueries == original.subqueries)
        #expect(changed.withRecursive)
    }

    @Test("Membership retains exact values and malformed operands fail explicitly")
    func membership() throws {
        let field = #field(\FluentPerson.age)
        let query = try FluentPerson.select().where(.matchesAny(of: [Int32(1), Int32(2)], at: field))
        #expect(query.definition.filter == .inList(.col("age"), values: [
            .literal(.queryValue(.primitive(.int32(1)))), .literal(.queryValue(.primitive(.int32(2))))]))
        #expect(throws: SelectionConstructionError.invalidCollectionOperand) {
            try FluentPerson.select().where(.comparison(FieldComparison(field: field, op: .in, value: FieldValue.int32(1))))
        }
    }
}
