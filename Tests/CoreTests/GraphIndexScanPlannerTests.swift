import Graph
import Testing

@Suite("Graph index scan planner")
struct GraphIndexScanPlannerTests {
    @Test(
        "Adjacency selects only physically maintained source or target orderings",
        arguments: adjacencyPatterns
    )
    func adjacencySelectsMaintainedOrdering(
        subjectBound: Bool,
        predicateBound: Bool,
        objectBound: Bool,
        expected: GraphIndexOrdering
    ) {
        let ordering = GraphIndexScanPlanner.ordering(
            strategy: .adjacency,
            subjectBound: subjectBound,
            predicateBound: predicateBound,
            objectBound: objectBound,
            graphBound: false
        )

        #expect(ordering == expected)
        #expect(ordering == .out || ordering == .in)
    }

    @Test(
        "Quad store selects triple-first ordering without a bound graph",
        arguments: boundPatterns
    )
    func quadStoreSelectsTripleFirstOrdering(
        subjectBound: Bool,
        predicateBound: Bool,
        objectBound: Bool,
        expected: GraphIndexOrdering
    ) {
        let ordering = GraphIndexScanPlanner.ordering(
            strategy: .quadStore,
            subjectBound: subjectBound,
            predicateBound: predicateBound,
            objectBound: objectBound,
            graphBound: false
        )

        #expect(ordering == expected)
        #expect(!ordering.isGraphFirst)
    }

    @Test(
        "Quad store selects graph-first ordering with a bound graph",
        arguments: boundPatterns
    )
    func quadStoreSelectsGraphFirstOrdering(
        subjectBound: Bool,
        predicateBound: Bool,
        objectBound: Bool,
        expected: GraphIndexOrdering
    ) {
        let ordering = GraphIndexScanPlanner.ordering(
            strategy: .quadStore,
            subjectBound: subjectBound,
            predicateBound: predicateBound,
            objectBound: objectBound,
            graphBound: true
        )

        #expect(ordering == graphFirstEquivalent(of: expected))
        #expect(ordering.isGraphFirst)
    }

    private static let boundPatterns: [(Bool, Bool, Bool, GraphIndexOrdering)] = [
        (true, true, true, .spo),
        (true, true, false, .spo),
        (true, false, true, .osp),
        (true, false, false, .spo),
        (false, true, true, .pos),
        (false, true, false, .pos),
        (false, false, true, .osp),
        (false, false, false, .spo),
    ]

    private static let adjacencyPatterns: [(Bool, Bool, Bool, GraphIndexOrdering)] = [
        (true, true, true, .out),
        (true, true, false, .out),
        (true, false, true, .out),
        (true, false, false, .out),
        (false, true, true, .in),
        (false, true, false, .out),
        (false, false, true, .in),
        (false, false, false, .out),
    ]

    private func graphFirstEquivalent(
        of ordering: GraphIndexOrdering
    ) -> GraphIndexOrdering {
        switch ordering {
        case .spo: return .gspo
        case .pos: return .gpos
        case .osp: return .gosp
        default:
            Issue.record("Unexpected triple-first ordering: \(ordering)")
            return .gspo
        }
    }
}
