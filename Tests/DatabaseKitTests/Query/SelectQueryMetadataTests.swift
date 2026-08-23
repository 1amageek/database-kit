import DatabaseKit
import Testing

@Suite("SELECT query metadata")
struct SelectQueryMetadataTests {
    @Test("Aggregation requires at least one grouping expression")
    func aggregationRequiresGroupingExpression() {
        let base = SelectQuery(
            projection: .all,
            source: .table(TableRef("Event"))
        )

        #expect(base.hasAggregation == false)
        #expect(base.replacing(groupBy: []).hasAggregation == false)
        #expect(
            base.replacing(
                groupBy: [.column(ColumnRef("calendarID"))]
            ).hasAggregation
        )
    }

    @Test("Referenced variables include every nested expression position")
    func referencedVariablesIncludeNestedExpressions() {
        let nested = SelectQuery(
            projection: .items([
                ProjectionItem(.variable(Variable("nestedProjection")))
            ]),
            source: .table(TableRef("Nested")),
            filter: .variable(Variable("nestedFilter"))
        )
        let expression = Expression.caseWhen(
            cases: [
                CaseWhenPair(
                    condition: .between(
                        .variable(Variable("value")),
                        low: .variable(Variable("low")),
                        high: .variable(Variable("high"))
                    ),
                    result: .aggregate(
                        .arrayAgg(
                            .variable(Variable("aggregate")),
                            orderBy: [
                                SortKey(.variable(Variable("aggregateOrder")))
                            ],
                            distinct: false
                        )
                    )
                )
            ],
            elseResult: .inSubquery(
                .variable(Variable("candidate")),
                subquery: nested
            )
        )

        #expect(
            expression.referencedVariables == [
                "aggregate",
                "aggregateOrder",
                "candidate",
                "high",
                "low",
                "nestedFilter",
                "nestedProjection",
                "value",
            ]
        )
    }
}
