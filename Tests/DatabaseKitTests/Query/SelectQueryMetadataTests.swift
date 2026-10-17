import DatabaseKit
import Testing

@Suite("SELECT query metadata")
struct SelectQueryMetadataTests {
    @Test("Aggregation requires at least one grouping expression")
    func aggregationRequiresGroupingExpression() {
        let base = SelectQuery(
            projection: [.wildcard()],
            source: .table(TableRef("Event"))
        )

        #expect(!base.source.usesSPARQLSemantics)
        let graphTable = SelectQuery(projection: [.wildcard()], source: .graphTable(
            GraphTableSource(graphName: "relationships", matchPattern: MatchPattern(paths: []))))
        #expect(!graphTable.source.usesSPARQLSemantics)
        #expect(base.hasAggregation == false)
        #expect(base.replacing(groupBy: []).hasAggregation == false)
        #expect(
            base.replacing(
                groupBy: [.expression(.column(ColumnRef("calendarID")))]
            ).hasAggregation
        )
    }
}
