/// A closed JSONB value whose collection views retain one nonrecursive owner.
public enum QueryJSONBNode: Sendable, Hashable {
    case null
    case bool(Bool)
    case string(String)
    case number(QueryNumericValue)
    case array(QueryJSONBElements)
    case object(QueryJSONBMembers)

    public var storageFootprint: QueryJSONBStorageFootprint {
        switch self {
        case .array(let values): return values.storage.footprint
        case .object(let values): return values.storage.footprint
        case .string(let value): return Self.scalarFootprint(bytes: UInt64(value.utf8.count))
        case .null, .bool, .number: return Self.scalarFootprint(bytes: 0)
        }
    }

    public static func array(_ values: [QueryJSONBNode],
                             limits: QueryValueLimits) throws(QueryValueError) -> Self {
        try admitComposite(count: values.count, limits: limits)
        var builder = QueryJSONBBuilder(limits: limits)
        var ids: [Int] = []
        for value in values { ids.append(try builder.appendTree(value)) }
        let root = try builder.appendArray(ids)
        return try builder.finish(root: root)
    }

    public static func object(_ values: [QueryJSONBMember],
                              limits: QueryValueLimits) throws(QueryValueError) -> Self {
        try admitComposite(count: values.count, limits: limits)
        var keyBytes: UInt64 = 0
        var previous: String?
        for value in values {
            if let previous, QueryJSONParser.compareKeys(previous, value.key) >= 0 {
                throw .nonCanonicalJSONB
            }
            guard !value.key.unicodeScalars.contains(where: { $0.value == 0 }) else { throw .nonCanonicalJSONB }
            let next = keyBytes.addingReportingOverflow(UInt64(value.key.utf8.count))
            guard !next.overflow else { throw .arithmeticOverflow }
            keyBytes = next.partialValue
            try QueryJSONParser.check(keyBytes, maximum: limits.maximumRetainedBytes, resource: "retainedBytes")
            previous = value.key
        }
        var builder = QueryJSONBBuilder(limits: limits)
        var ids: [QueryJSONBIndexedMember] = []
        for value in values {
            ids.append(QueryJSONBIndexedMember(key: value.key, value: try builder.appendTree(value.value)))
        }
        let root = try builder.appendObject(ids)
        return try builder.finish(root: root)
    }

    private static func scalarFootprint(bytes: UInt64) -> QueryJSONBStorageFootprint {
        QueryJSONBStorageFootprint(nodeCapacity: 0, elementIndexCapacity: 0, memberCapacity: 0,
                                   retainedStorageByteCount: 0, utf8ByteCount: bytes)
    }

    private static func admitComposite(count: Int, limits: QueryValueLimits) throws(QueryValueError) {
        let minimumNodes = UInt64(count).addingReportingOverflow(1)
        guard !minimumNodes.overflow else { throw .arithmeticOverflow }
        try QueryJSONParser.check(minimumNodes.partialValue, maximum: limits.maximumTotalNodes, resource: "nodes")
        try QueryJSONParser.check(UInt64(count), maximum: limits.maximumCollectionElements, resource: "collectionElements")
        try QueryJSONParser.check(count == 0 ? 1 : 2, maximum: limits.maximumNestingDepth, resource: "depth")
    }

    private enum PairVisit {
        case nodes(QueryJSONBNode, QueryJSONBNode)
        case arrays(QueryJSONBElements, QueryJSONBElements, Int)
        case objects(QueryJSONBMembers, QueryJSONBMembers, Int)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        var stack: [PairVisit] = [.nodes(lhs, rhs)]
        while let visit = stack.popLast() {
            switch visit {
            case .nodes(let left, let right):
                switch (left, right) {
                case (.null, .null): break
                case (.bool(let a), .bool(let b)): if a != b { return false }
                case (.string(let a), .string(let b)): if !a.utf8.elementsEqual(b.utf8) { return false }
                case (.number(let a), .number(let b)): if a != b { return false }
                case (.array(let a), .array(let b)):
                    if a.count != b.count { return false }
                    if !a.isEmpty { stack.append(.arrays(a, b, 0)) }
                case (.object(let a), .object(let b)):
                    if a.count != b.count { return false }
                    if !a.isEmpty { stack.append(.objects(a, b, 0)) }
                default: return false
                }
            case .arrays(let a, let b, let index):
                if index + 1 < a.count { stack.append(.arrays(a, b, index + 1)) }
                stack.append(.nodes(a[index], b[index]))
            case .objects(let a, let b, let index):
                let left = a[index], right = b[index]
                if !left.key.utf8.elementsEqual(right.key.utf8) { return false }
                if index + 1 < a.count { stack.append(.objects(a, b, index + 1)) }
                stack.append(.nodes(left.value, right.value))
            }
        }
        return true
    }

    private enum HashVisit {
        case node(QueryJSONBNode)
        case array(QueryJSONBElements, Int)
        case object(QueryJSONBMembers, Int)
    }

    public func hash(into hasher: inout Hasher) {
        var stack: [HashVisit] = [.node(self)]
        while let visit = stack.popLast() {
            switch visit {
            case .node(let node):
                switch node {
                case .null: hasher.combine(0)
                case .bool(let value): hasher.combine(1); hasher.combine(value)
                case .string(let value): hasher.combine(2); Self.hashString(value, into: &hasher)
                case .number(let value): hasher.combine(3); hasher.combine(value)
                case .array(let values):
                    hasher.combine(4); hasher.combine(values.count)
                    if !values.isEmpty { stack.append(.array(values, 0)) }
                case .object(let values):
                    hasher.combine(5); hasher.combine(values.count)
                    if !values.isEmpty { stack.append(.object(values, 0)) }
                }
            case .array(let values, let index):
                if index + 1 < values.count { stack.append(.array(values, index + 1)) }
                stack.append(.node(values[index]))
            case .object(let values, let index):
                let member = values[index]
                Self.hashString(member.key, into: &hasher)
                if index + 1 < values.count { stack.append(.object(values, index + 1)) }
                stack.append(.node(member.value))
            }
        }
    }

    private static func hashString(_ value: String, into hasher: inout Hasher) {
        hasher.combine(value.utf8.count)
        for byte in value.utf8 { hasher.combine(byte) }
    }
}
