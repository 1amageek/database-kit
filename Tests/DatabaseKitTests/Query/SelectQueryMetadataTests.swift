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
}
