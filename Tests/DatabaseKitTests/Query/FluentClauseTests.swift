import DatabaseKit
import DatabaseTypes
import Testing

@Suite("Canonical fluent clauses")
struct FluentClauseTests {
    @Test("Complete clauses retain CTE scope, grouping, windows and immutable branches")
    func completeClauses() throws {
        let cte = NamedSubquery(name: "walk", columns: ["id"], query: TableRef("items").select("id"),
            materialized: .notMaterialized,
            search: CTESearchClause(order: .depthFirst, columns: ["id"], sequenceColumn: "sequence"),
            cycle: CTECycleClause(columns: ["id"], markColumn: "cycle", pathColumn: "path",
                markValue: .string("yes"), defaultValue: .string("no")))
        let window = NamedWindow(name: "w", specification: WindowSpecification(partitionBy: [.col("id")]))
        let base = TableRef("walk").selectAll().with(cte).withRecursive()
        let query = try base.selectDistinct("id", "id").where("id", .greaterThan, Int16(2))
            .groupBy(elements: [.rollup([[.col("id")]])]).having(.isNotNull(.col("id")))
            .window(window).orderByDesc("id").paginate(pageIndex: 2, pageSize: 3)
        #expect(query.subqueries == [cte] && query.withRecursive)
        #expect(query.projection == [ProjectionItem(.col("id")), ProjectionItem(.col("id"))])
        #expect(query.quantifier == .distinct)
        #expect(query.filter == .greaterThan(.col("id"), .int(2)))
        #expect(query.groupBy == [.rollup([[.col("id")]])] && query.windows == [window])
        #expect(query.having == .isNotNull(.col("id")))
        #expect(query.orderBy == [SortKey(.col("id"), direction: .descending)])
        #expect(query.pagination == QueryPagination(limit: .count(.fixed(3), withTies: false), offset: .fixed(6)))
        #expect(base.projection == [.wildcard()] && base.filter == nil && base.groupBy == nil)
        #expect(base.groupBy(elements: []).groupBy == [])
        try QueryStructuralValidator.validate(query)
    }

    @Test("Joined source references preserve schema, aliases, partitions and USING order")
    func joinedSources() throws {
        let partitions = try FieldObject([("region", .string("east"))])
        let left = TableRef(schema: "Exact", table: "items", alias: "i", partitions: partitions)
        let right = TableRef(schema: "Exact", table: "other", alias: "o", partitions: partitions)
        let condition = Expression.equal(.column(ColumnRef(table: "i", column: "id")),
            .column(ColumnRef(table: "o", column: "id")))
        let query = left.selectAll().leftJoin(right, on: condition).rightJoin("last", on: .literal(.bool(true)))
            .join("keys", using: "id", "region")
        guard case .join(let usingJoin) = query.source,
            case .join(let rightJoin) = usingJoin.left,
            case .join(let leftJoin) = rightJoin.left else {
            Issue.record("Expected ordered nested joins")
            return
        }
        #expect(usingJoin.condition == .using(["id", "region"]))
        #expect(rightJoin.type == .right && leftJoin.type == .left)
        #expect(leftJoin.left == left.querySource && leftJoin.right == right.querySource)
        #expect(leftJoin.condition == .on(condition))
        #expect(left.selectAll().join(right, on: condition).source == .join(JoinClause(
            type: .inner, left: left.querySource, right: right.querySource, condition: .on(condition))))
    }

    @Test("Clause replacement retains access hints and explicit language metadata")
    func untouchedMetadata() {
        let hint = AccessPath.index(IndexScanSource(indexName: "items_age", indexType: .ordered))
        let dataset = SPARQLDataset.explicit(defaultGraphs: ["urn:default"], namedGraphs: ["urn:named"])
        let base = SelectQuery(projection: [.wildcard()], source: .table(TableRef("items")),
            accessPath: hint, reduced: true, dataset: dataset)
        let changed = base.select("age", as: "value").whereNull("missing").groupBy("age")
            .having(.literal(.bool(true))).window().orderBy("age").limit(7).offset(2)
        #expect(changed.accessPath == hint && changed.reduced && changed.dataset == dataset)
        #expect(base.projection == [.wildcard()] && base.filter == nil)
        let pattern = MatchPattern(paths: [])
        let graph = changed.graphTable("social", match: pattern, columns: [(.col("age"), "value")])
        #expect(graph.source == .graphTable(GraphTableSource(graphName: "social", matchPattern: pattern,
            columns: [GraphTableColumn(expression: .col("age"), alias: "value")])))
        #expect(graph.accessPath == hint && graph.dataset == dataset && graph.pagination == changed.pagination)
        #expect(changed.graphTable("social", match: pattern).projection == changed.projection)
    }

    @Test("Literal conditions and aggregate conveniences retain exact canonical meaning")
    func conditionsAndAggregates() throws {
        let base = TableRef("items").selectAll()
        #expect(try base.where("n", equals: UInt64.max).filter == .equal(.col("n"), .literal(.uint(.max))))
        let query = try base.whereIn("n", [Int16(1), Int16(2)]).whereNotIn("n", [Literal.int(3)])
            .whereBetween("n", Int16(0), Int16(9)).whereLike("name", pattern: "a_%")
            .whereNotNull("name")
        try QueryStructuralValidator.validate(query)
        #expect(throws: QueryLiteralConversionError.unsupportedFieldValue) {
            try base.where("value", equals: FieldValue.object(FieldObject()))
        }
        let aggregates: [(SelectQuery, SQLAggregateFunction, [Expression])] = [
            (base.count(), .count, []), (base.sum("n"), .sum, [.col("n")]),
            (base.avg("n"), .avg, [.col("n")]), (base.max("n"), .max, [.col("n")]),
            (base.min("n"), .min, [.col("n")])]
        for (query, function, arguments) in aggregates {
            #expect(query.projection == [ProjectionItem(.aggregate(.sql(SQLAggregateCall(
                function: function, arguments: arguments))), alias: function.rawValue)])
        }
    }
}
