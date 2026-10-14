extension QueryJSONBBuilder {
    private enum CopyParent {
        case array(QueryJSONBElements, index: Int, children: [Int])
        case object(QueryJSONBMembers, index: Int, children: [QueryJSONBIndexedMember])
    }

    /// Copies an already-owned logical subtree; production decoders append IDs directly.
    mutating func appendTree(_ root: QueryJSONBNode) throws(QueryValueError) -> Int {
        let baseline = appendedNodeCount
        var visited: UInt64 = 0
        var parents: [CopyParent] = []
        try admitNextCopyNode(baseline: baseline, visited: visited, parentCount: 0, descent: false)
        var current = root
        while true {
            visited += 1
            var completed: Int
            switch current {
            case .null, .bool, .string, .number: completed = try append(current)
            case .array(let values):
                if !values.isEmpty {
                    try admitNextCopyNode(baseline: baseline, visited: visited,
                                          parentCount: parents.count, descent: true)
                    parents.append(.array(values, index: 0, children: []))
                    current = values[0]
                    continue
                }
                completed = try appendArray([])
            case .object(let values):
                if !values.isEmpty {
                    try admitNextCopyNode(baseline: baseline, visited: visited,
                                          parentCount: parents.count, descent: true)
                    parents.append(.object(values, index: 0, children: []))
                    current = values[0].value
                    continue
                }
                completed = try appendObject([])
            }
            var hasNext = false
            while let parent = parents.popLast() {
                switch parent {
                case .array(let values, let index, var children):
                    children.append(completed)
                    let next = index + 1
                    if next < values.count {
                        try admitNextCopyNode(baseline: baseline, visited: visited,
                                              parentCount: parents.count, descent: true)
                        parents.append(.array(values, index: next, children: children))
                        current = values[next]
                        hasNext = true
                    } else { completed = try appendArray(children) }
                case .object(let values, let index, var children):
                    children.append(QueryJSONBIndexedMember(key: values[index].key, value: completed))
                    let next = index + 1
                    if next < values.count {
                        try admitNextCopyNode(baseline: baseline, visited: visited,
                                              parentCount: parents.count, descent: true)
                        parents.append(.object(values, index: next, children: children))
                        current = values[next].value
                        hasNext = true
                    } else { completed = try appendObject(children) }
                }
                if hasNext { break }
            }
            if !hasNext { return completed }
        }
    }

    private func admitNextCopyNode(baseline: UInt64, visited: UInt64,
                                   parentCount: Int, descent: Bool) throws(QueryValueError) {
        // Reserve the enclosing public factory root and the next logical node.
        let pending = visited.addingReportingOverflow(2)
        let nodes = baseline.addingReportingOverflow(pending.partialValue)
        let depth = UInt64(parentCount).addingReportingOverflow(descent ? 3 : 2)
        guard !pending.overflow, !nodes.overflow, !depth.overflow else { throw .arithmeticOverflow }
        try admitCopyTraversal(nodeCount: nodes.partialValue, depth: depth.partialValue)
    }
}
