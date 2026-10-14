extension QueryJSONParser {
    private enum ValidationCursor {
        case array(QueryJSONBElements, index: Int, depth: UInt64)
        case object(QueryJSONBMembers, index: Int, depth: UInt64)
    }

    static func measure(root: QueryJSONBNode, limits: QueryValueLimits) throws(QueryValueError) -> QueryValueFootprint {
        try check(1, maximum: limits.maximumTotalNodes, resource: "nodes")
        try check(1, maximum: limits.maximumNestingDepth, resource: "depth")
        let storage = root.storageFootprint
        let combinedBytes = storage.retainedStorageByteCount.addingReportingOverflow(storage.utf8ByteCount)
        guard !combinedBytes.overflow else { throw .arithmeticOverflow }
        let retainedBytes = combinedBytes.partialValue
        try check(retainedBytes, maximum: limits.maximumRetainedBytes, resource: "retainedBytes")
        var cursors: [ValidationCursor] = []
        var current: (node: QueryJSONBNode, depth: UInt64)? = (root, 1)
        var nodes: UInt64 = 1
        var elements: UInt64 = 0
        var maximumDepth: UInt64 = 1
        while let entry = current {
            current = nil
            switch entry.node {
            case .null, .bool, .number: break
            case .string(let value):
                try validateString(value)
            case .array(let values):
                let depth = try admitChildren(values.count, parentDepth: entry.depth, nodes: &nodes, elements: &elements, limits: limits)
                if !values.isEmpty {
                    maximumDepth = max(maximumDepth, depth)
                    cursors.append(.array(values, index: 0, depth: depth))
                }
            case .object(let members):
                let depth = try admitChildren(members.count, parentDepth: entry.depth, nodes: &nodes, elements: &elements, limits: limits)
                if !members.isEmpty {
                    maximumDepth = max(maximumDepth, depth)
                    cursors.append(.object(members, index: 0, depth: depth))
                }
            }
            if let cursor = cursors.popLast() {
                switch cursor {
                case .array(let values, let index, let depth):
                    if index + 1 < values.count {
                        cursors.append(.array(values, index: index + 1, depth: depth))
                    }
                    current = (values[index], depth)
                case .object(let members, let index, let depth):
                    let member = members[index]
                    if index > 0, compareKeys(members[index - 1].key, member.key) >= 0 {
                        throw .nonCanonicalJSONB
                    }
                    try validateString(member.key)
                    if index + 1 < members.count {
                        cursors.append(.object(members, index: index + 1, depth: depth))
                    }
                    current = (member.value, depth)
                }
            }
        }
        return QueryValueFootprint(nodeCount: nodes, collectionElementCount: elements, retainedByteCount: retainedBytes, maximumNestingDepth: maximumDepth)
    }

    private static func validateString(_ value: String) throws(QueryValueError) {
        guard !value.unicodeScalars.contains(where: { $0.value == 0 }) else { throw .nonCanonicalJSONB }
    }

    private static func admitChildren(
        _ count: Int, parentDepth: UInt64, nodes: inout UInt64,
        elements: inout UInt64, limits: QueryValueLimits
    ) throws(QueryValueError) -> UInt64 {
        let nextNodes = nodes.addingReportingOverflow(UInt64(count))
        let nextElements = elements.addingReportingOverflow(UInt64(count))
        let depth = parentDepth.addingReportingOverflow(count == 0 ? 0 : 1)
        guard !nextNodes.overflow, !nextElements.overflow, !depth.overflow else { throw .arithmeticOverflow }
        try check(nextNodes.partialValue, maximum: limits.maximumTotalNodes, resource: "nodes")
        try check(nextElements.partialValue, maximum: limits.maximumCollectionElements, resource: "collectionElements")
        try check(depth.partialValue, maximum: limits.maximumNestingDepth, resource: "depth")
        nodes = nextNodes.partialValue
        elements = nextElements.partialValue
        return depth.partialValue
    }
}
