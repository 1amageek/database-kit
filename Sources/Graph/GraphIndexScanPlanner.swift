import DatabaseTypes
/// Pure ordering selection shared by every graph execution path.
public enum GraphIndexScanPlanner {
    public static func ordering(
        strategy: GraphIndexStrategy,
        subjectBound: Bool,
        predicateBound: Bool,
        objectBound: Bool,
        graphBound: Bool
    ) -> GraphIndexOrdering {
        if strategy == .adjacency {
            if subjectBound { return .out }
            if objectBound { return .in }
            return .out
        }

        let graphFirst: Bool
        switch strategy {
        case .namedGraphStore:
            graphFirst = true
        case .quadStore:
            graphFirst = graphBound
        case .adjacency, .tripleStore, .hexastore:
            graphFirst = false
        }

        switch (subjectBound, predicateBound, objectBound) {
        case (true, true, true), (true, true, false), (true, false, false):
            if graphFirst { return .gspo }
            return .spo
        case (true, false, true):
            if graphFirst { return .gosp }
            return strategy == .hexastore ? .sop : .osp
        case (false, true, true), (false, true, false):
            if graphFirst { return .gpos }
            return .pos
        case (false, false, true):
            if graphFirst { return .gosp }
            return .osp
        case (false, false, false):
            if graphFirst { return .gspo }
            return .spo
        }
    }
}
