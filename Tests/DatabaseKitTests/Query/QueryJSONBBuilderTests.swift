import DatabaseKit
import Testing

@Suite("Planned public JSONB construction")
struct QueryJSONBBuilderTests {
    private var limits: QueryValueLimits {
        QueryValueLimits(maximumRetainedBytes: 4_000_000, maximumTotalNodes: 10_000,
                         maximumNestingDepth: 5_000, maximumCollectionElements: 10_000)
    }

    @Test("Planned object construction reports all scratch capacities and preserves UTF-8 separately")
    func plannedConstruction() throws {
        let selected = try QueryJSONBBuilder.constructionByteCount(nodeCapacity: 3, elementIndexCapacity: 1, memberCapacity: 1)
        let empty = try QueryJSONBBuilder.constructionByteCount(nodeCapacity: 0, elementIndexCapacity: 0, memberCapacity: 0)
        #expect(empty > 0 && selected > empty)
        var builder = try QueryJSONBBuilder(limits: limits, nodeCapacity: 3, elementIndexCapacity: 1, memberCapacity: 1)
        let actual = builder.constructionRetainedByteCount
        #expect(actual >= selected)
        let leaf = try builder.append(.string("é"))
        let array = try builder.appendArray([leaf])
        let root = try builder.appendObject([QueryJSONBIndexedMember(key: "a", value: array)])
        #expect(builder.constructionRetainedByteCount == actual)
        let value = try builder.finish(root: root)
        #expect(value.storageFootprint.utf8ByteCount == 3)
        #expect(actual > value.storageFootprint.retainedStorageByteCount)
        guard case .object(let members) = value, case .array(let elements) = members[0].value else {
            Issue.record("Expected a nested public builder destination"); return
        }
        #expect(elements[0] == .string("é"))
    }

    @Test("Each selected ceiling rejects one-past before hidden growth and poisons failure")
    func plannedCeilings() throws {
        var nodes = try QueryJSONBBuilder(limits: limits, nodeCapacity: 1, elementIndexCapacity: 0, memberCapacity: 0)
        _ = try nodes.append(.null)
        let before = nodes.constructionRetainedByteCount
        #expect(throws: QueryValueError.resourceLimit(resource: "jsonbPlannedNodeCapacity", actual: 2, maximum: 1)) {
            try nodes.append(.bool(true))
        }
        #expect(nodes.constructionRetainedByteCount == before)
        #expect(throws: QueryValueError.nonCanonicalJSONB) { try nodes.append(.null) }
        var indices = try QueryJSONBBuilder(limits: limits, nodeCapacity: 2, elementIndexCapacity: 0, memberCapacity: 0)
        let leaf = try indices.append(.null)
        #expect(throws: QueryValueError.resourceLimit(resource: "jsonbPlannedElementIndexCapacity", actual: 1, maximum: 0)) {
            try indices.appendArray([leaf])
        }
        var members = try QueryJSONBBuilder(limits: limits, nodeCapacity: 2, elementIndexCapacity: 0, memberCapacity: 0)
        let child = try members.append(.null)
        #expect(throws: QueryValueError.resourceLimit(resource: "jsonbPlannedMemberCapacity", actual: 1, maximum: 0)) {
            try members.appendObject([QueryJSONBIndexedMember(key: "a", value: child)])
        }
    }

    @Test("Invalid selected capacities limits canonical keys and repeated ownership fail explicitly")
    func invalidConstruction() throws {
        #expect(throws: QueryValueError.nonCanonicalJSONB) {
            try QueryJSONBBuilder.constructionByteCount(nodeCapacity: -1, elementIndexCapacity: 0, memberCapacity: 0)
        }
        #expect(throws: QueryValueError.arithmeticOverflow) {
            try QueryJSONBBuilder.constructionByteCount(nodeCapacity: Int.max, elementIndexCapacity: Int.max, memberCapacity: Int.max)
        }
        let bounded = QueryValueLimits(maximumRetainedBytes: 100_000, maximumTotalNodes: 1,
            maximumNestingDepth: 1, maximumCollectionElements: 1)
        #expect(throws: QueryValueError.self) {
            try QueryJSONBBuilder(limits: bounded, nodeCapacity: 2, elementIndexCapacity: 0, memberCapacity: 0)
        }
        var repeated = QueryJSONBBuilder(limits: limits)
        let child = try repeated.append(.null)
        #expect(throws: QueryValueError.nonCanonicalJSONB) { try repeated.appendArray([child, child]) }
        var unordered = QueryJSONBBuilder(limits: limits)
        let first = try unordered.append(.null), second = try unordered.append(.null)
        #expect(throws: QueryValueError.nonCanonicalJSONB) {
            try unordered.appendObject([.init(key: "b", value: first), .init(key: "a", value: second)])
        }
    }

    @Test("Deep destination and retained subtree share one nonrecursive owner after builder release")
    func deepRetainedOwner() throws {
        func retainedChild() throws(QueryValueError) -> QueryJSONBNode {
            var builder = try QueryJSONBBuilder(limits: limits, nodeCapacity: 2049, elementIndexCapacity: 2048, memberCapacity: 0)
            var root = try builder.append(.string("leaf"))
            for _ in 0..<2048 { root = try builder.appendArray([root]) }
            let result = try builder.finish(root: root)
            guard case .array(let children) = result else { throw .nonCanonicalJSONB }
            let child = children[0]
            #expect(child.storageFootprint == result.storageFootprint)
            return child
        }
        var value = try retainedChild()
        for _ in 0..<2047 {
            guard case .array(let children) = value else { Issue.record("Lost retained subtree"); return }
            value = children[0]
        }
        #expect(value == .string("leaf"))
    }
}
