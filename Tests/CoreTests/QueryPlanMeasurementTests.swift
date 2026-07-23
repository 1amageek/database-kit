import Testing
@testable import Core

@Suite("Query plan measurements")
struct QueryPlanMeasurementTests {
    @Test("Unmeasured estimates remain absent")
    func unmeasuredEstimatesRemainAbsent() {
        let plan = QueryPlan(planType: .tableScan)
        let statistics = QueryExecutionStats(
            plan: plan,
            actualRows: 3,
            executionTime: 0.01
        )

        #expect(plan.estimatedCost == nil)
        #expect(plan.estimatedRows == nil)
        #expect(statistics.bytesRead == nil)
        #expect(statistics.transactionRetries == nil)
    }

    @Test("Measured values preserve zero")
    func measuredValuesPreserveZero() {
        let plan = QueryPlan(
            planType: .indexScan,
            estimatedCost: 0,
            estimatedRows: 0
        )
        let statistics = QueryExecutionStats(
            plan: plan,
            actualRows: 0,
            executionTime: 0,
            bytesRead: 0,
            transactionRetries: 0
        )

        #expect(plan.estimatedCost == 0)
        #expect(plan.estimatedRows == 0)
        #expect(statistics.bytesRead == 0)
        #expect(statistics.transactionRetries == 0)
    }
}
