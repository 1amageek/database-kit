import DatabaseTypes

public enum GraphAlgorithmOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.graphAlgorithm

    public enum GraphSelector: Sendable, Hashable {
        case all
        case defaultGraph
        case named(Term)

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .all:
                writer.writeUInt8(1)
            case .defaultGraph:
                writer.writeUInt8(2)
            case .named(let name):
                writer.writeUInt8(3)
                try name.encode(into: &writer)
            }
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1:
                self = .all
            case 2:
                self = .defaultGraph
            case 3:
                self = .named(try Term(from: &reader))
            case let tag:
                throw .invalidValueTag(tag)
            }
        }
    }

    public struct Source: DatabaseWireValue, Hashable {
        public let index: String
        public let partitions: FieldObject
        public let graph: GraphSelector
        public let edgeLabel: Term?

        public init(
            index: String,
            partitions: FieldObject = FieldObject(),
            graph: GraphSelector = .all,
            edgeLabel: Term? = nil
        ) {
            self.index = index
            self.partitions = partitions
            self.graph = graph
            self.edgeLabel = edgeLabel
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeString(index)
            try partitions.encode(into: &writer)
            try graph.encode(into: &writer)
            writer.writeBool(edgeLabel != nil)
            if let edgeLabel { try edgeLabel.encode(into: &writer) }
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let index = try reader.readString()
            self.init(
                index: index,
                partitions: try FieldObject(from: &reader),
                graph: try GraphSelector(from: &reader),
                edgeLabel: try reader.readBool()
                    ? try Term(from: &reader)
                    : nil
            )
        }
    }

    public enum LimitReason: UInt8, Sendable, Hashable {
        case maximumDepth = 1
        case maximumNodes = 2
        case maximumWeight = 3
        case maximumIterations = 4
        case maximumResults = 5
        case maximumWorkUnits = 6

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let rawValue = try reader.readUInt8()
            guard let value = Self(rawValue: rawValue) else {
                throw .invalidValueTag(rawValue)
            }
            self = value
        }
    }

    public struct Progress: DatabaseWireValue, Hashable {
        public let algorithmComplete: Bool
        public let resultPageComplete: Bool
        public let limitReason: LimitReason?
        public let continuation: ByteString?

        public init(
            algorithmComplete: Bool,
            resultPageComplete: Bool,
            limitReason: LimitReason? = nil,
            continuation: ByteString? = nil
        ) {
            self.algorithmComplete = algorithmComplete
            self.resultPageComplete = resultPageComplete
            self.limitReason = limitReason
            self.continuation = continuation
        }

        public static let complete = Progress(
            algorithmComplete: true,
            resultPageComplete: true
        )

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try validate()
            writer.writeBool(algorithmComplete)
            writer.writeBool(resultPageComplete)
            writer.writeBool(limitReason != nil)
            if let limitReason {
                writer.writeUInt8(limitReason.rawValue)
            }
            try writer.writeOptionalBytes(continuation)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let algorithmComplete = try reader.readBool()
            let resultPageComplete = try reader.readBool()
            let limitReason = try reader.readBool()
                ? try LimitReason(from: &reader)
                : nil
            let continuation = try reader.readOptionalBytes()
            self.init(
                algorithmComplete: algorithmComplete,
                resultPageComplete: resultPageComplete,
                limitReason: limitReason,
                continuation: continuation
            )
            try validate()
        }

        private func validate() throws(DatabaseWireError) {
            guard !(algorithmComplete && limitReason != nil) else {
                throw .invalidGraphProgress
            }
            guard resultPageComplete || continuation != nil else {
                throw .invalidGraphProgress
            }
            guard algorithmComplete || continuation != nil || limitReason != nil else {
                throw .invalidGraphProgress
            }
            guard !(algorithmComplete && resultPageComplete && continuation != nil) else {
                throw .invalidGraphProgress
            }
        }
    }

    public enum Invocation: Sendable, Hashable {
        case shortestPath(
            source: Term,
            target: Term,
            maximumDepth: UInt32,
            bidirectional: Bool,
            maximumNodes: UInt64
        )
        case weightedShortestPath(
            source: Term,
            target: Term,
            weightProperty: String,
            maximumWeight: Double,
            maximumNodes: UInt64
        )
        case pageRank(
            dampingFactor: Double,
            maximumIterations: UInt32,
            convergenceThreshold: Double,
            personalizedSource: Term?
        )
        case community(
            maximumIterations: UInt32,
            computeModularity: Bool,
            minimumCommunitySize: UInt32,
            seed: UInt64?
        )
        case cycleDetection(maximumCycles: UInt32, maximumNodes: UInt64)
        case stronglyConnectedComponents(
            maximumComponents: UInt32,
            maximumNodes: UInt64
        )
        case topologicalSort(maximumNodes: UInt64)

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .shortestPath(
                let source,
                let target,
                let maximumDepth,
                let bidirectional,
                let maximumNodes
            ):
                writer.writeUInt8(1)
                try source.encode(into: &writer)
                try target.encode(into: &writer)
                writer.writeUInt32(maximumDepth)
                writer.writeBool(bidirectional)
                writer.writeUInt64(maximumNodes)
            case .weightedShortestPath(
                let source,
                let target,
                let weightProperty,
                let maximumWeight,
                let maximumNodes
            ):
                writer.writeUInt8(2)
                try source.encode(into: &writer)
                try target.encode(into: &writer)
                try writer.writeString(weightProperty)
                writer.writeDouble(maximumWeight)
                writer.writeUInt64(maximumNodes)
            case .pageRank(
                let dampingFactor,
                let maximumIterations,
                let convergenceThreshold,
                let personalizedSource
            ):
                writer.writeUInt8(3)
                writer.writeDouble(dampingFactor)
                writer.writeUInt32(maximumIterations)
                writer.writeDouble(convergenceThreshold)
                writer.writeBool(personalizedSource != nil)
                if let personalizedSource {
                    try personalizedSource.encode(into: &writer)
                }
            case .community(
                let maximumIterations,
                let computeModularity,
                let minimumCommunitySize,
                let seed
            ):
                writer.writeUInt8(4)
                writer.writeUInt32(maximumIterations)
                writer.writeBool(computeModularity)
                writer.writeUInt32(minimumCommunitySize)
                writer.writeBool(seed != nil)
                if let seed { writer.writeUInt64(seed) }
            case .cycleDetection(let maximumCycles, let maximumNodes):
                writer.writeUInt8(5)
                writer.writeUInt32(maximumCycles)
                writer.writeUInt64(maximumNodes)
            case .stronglyConnectedComponents(
                let maximumComponents,
                let maximumNodes
            ):
                writer.writeUInt8(6)
                writer.writeUInt32(maximumComponents)
                writer.writeUInt64(maximumNodes)
            case .topologicalSort(let maximumNodes):
                writer.writeUInt8(7)
                writer.writeUInt64(maximumNodes)
            }
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1:
                self = .shortestPath(
                    source: try Term(from: &reader),
                    target: try Term(from: &reader),
                    maximumDepth: try reader.readUInt32(),
                    bidirectional: try reader.readBool(),
                    maximumNodes: try reader.readUInt64()
                )
            case 2:
                self = .weightedShortestPath(
                    source: try Term(from: &reader),
                    target: try Term(from: &reader),
                    weightProperty: try reader.readString(),
                    maximumWeight: try reader.readDouble(),
                    maximumNodes: try reader.readUInt64()
                )
            case 3:
                self = .pageRank(
                    dampingFactor: try reader.readDouble(),
                    maximumIterations: try reader.readUInt32(),
                    convergenceThreshold: try reader.readDouble(),
                    personalizedSource: try reader.readBool()
                        ? try Term(from: &reader)
                        : nil
                )
            case 4:
                let maximumIterations = try reader.readUInt32()
                let computeModularity = try reader.readBool()
                let minimumCommunitySize = try reader.readUInt32()
                let seed = try reader.readBool() ? try reader.readUInt64() : nil
                self = .community(
                    maximumIterations: maximumIterations,
                    computeModularity: computeModularity,
                    minimumCommunitySize: minimumCommunitySize,
                    seed: seed
                )
            case 5:
                self = .cycleDetection(
                    maximumCycles: try reader.readUInt32(),
                    maximumNodes: try reader.readUInt64()
                )
            case 6:
                self = .stronglyConnectedComponents(
                    maximumComponents: try reader.readUInt32(),
                    maximumNodes: try reader.readUInt64()
                )
            case 7:
                self = .topologicalSort(maximumNodes: try reader.readUInt64())
            case let tag:
                throw .invalidValueTag(tag)
            }
        }
    }

    public struct Page: DatabaseWireValue, Hashable {
        public let limit: UInt32
        public let continuation: ByteString?

        public init(limit: UInt32 = 1_000, continuation: ByteString? = nil) {
            self.limit = limit
            self.continuation = continuation
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeUInt32(limit)
            try writer.writeOptionalBytes(continuation)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                limit: try reader.readUInt32(),
                continuation: try reader.readOptionalBytes()
            )
        }
    }

    public struct Request: DatabaseWireValue, Hashable {
        public let source: Source
        public let invocation: Invocation
        public let page: Page
        public let budget: ExecutionBudget

        public init(
            source: Source,
            invocation: Invocation,
            page: Page = Page(),
            budget: ExecutionBudget = ExecutionBudget()
        ) {
            self.source = source
            self.invocation = invocation
            self.page = page
            self.budget = budget
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try source.encode(into: &writer)
            try invocation.encode(into: &writer)
            try page.encode(into: &writer)
            try budget.encode(into: &writer)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                source: try Source(from: &reader),
                invocation: try Invocation(from: &reader),
                page: try Page(from: &reader),
                budget: try ExecutionBudget(from: &reader)
            )
        }
    }

    public struct PathResult: DatabaseWireValue, Hashable {
        public let found: Bool
        public let nodes: [Term]
        public let edgeLabels: [Term]
        public let weights: [Double]
        public let totalWeight: Double?
        public let nodesExplored: UInt64
        public let durationNanoseconds: UInt64
        public let progress: Progress

        public init(
            found: Bool,
            nodes: [Term],
            edgeLabels: [Term] = [],
            weights: [Double] = [],
            totalWeight: Double? = nil,
            nodesExplored: UInt64,
            durationNanoseconds: UInt64,
            progress: Progress
        ) {
            self.found = found
            self.nodes = nodes
            self.edgeLabels = edgeLabels
            self.weights = weights
            self.totalWeight = totalWeight
            self.nodesExplored = nodesExplored
            self.durationNanoseconds = durationNanoseconds
            self.progress = progress
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try validate()
            writer.writeBool(found)
            try Self.encodeTerms(nodes, into: &writer)
            try Self.encodeTerms(edgeLabels, into: &writer)
            try writer.writeCount(weights.count)
            for weight in weights { writer.writeDouble(weight) }
            writer.writeBool(totalWeight != nil)
            if let totalWeight { writer.writeDouble(totalWeight) }
            writer.writeUInt64(nodesExplored)
            writer.writeUInt64(durationNanoseconds)
            try progress.encode(into: &writer)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let found = try reader.readBool()
            let nodes = try Self.decodeTerms(from: &reader)
            let edgeLabels = try Self.decodeTerms(from: &reader)
            let weightCount = try reader.readCount()
            var weights: [Double] = []
            weights.reserveCapacity(weightCount)
            for _ in 0..<weightCount { weights.append(try reader.readDouble()) }
            self.init(
                found: found,
                nodes: nodes,
                edgeLabels: edgeLabels,
                weights: weights,
                totalWeight: try reader.readBool() ? try reader.readDouble() : nil,
                nodesExplored: try reader.readUInt64(),
                durationNanoseconds: try reader.readUInt64(),
                progress: try Progress(from: &reader)
            )
            try validate()
        }

        private func validate() throws(DatabaseWireError) {
            guard found ? !nodes.isEmpty : nodes.isEmpty else {
                throw .invalidGraphResult
            }
            guard !found || progress.algorithmComplete else {
                throw .invalidGraphResult
            }
            guard edgeLabels.isEmpty || edgeLabels.count + 1 == nodes.count else {
                throw .invalidGraphResult
            }
            guard weights.isEmpty || weights.count + 1 == nodes.count else {
                throw .invalidGraphResult
            }
            guard totalWeight == nil || found else {
                throw .invalidGraphResult
            }
        }
    }

    public struct Score: DatabaseWireValue, Hashable {
        public let vertex: Term
        public let score: Double

        public init(vertex: Term, score: Double) {
            self.vertex = vertex
            self.score = score
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try vertex.encode(into: &writer)
            writer.writeDouble(score)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                vertex: try Term(from: &reader),
                score: try reader.readDouble()
            )
        }
    }

    public struct RankingPage: DatabaseWireValue, Hashable {
        public let scores: [Score]
        public let iterations: UInt32
        public let convergenceDelta: Double
        public let progress: Progress

        public init(
            scores: [Score],
            iterations: UInt32,
            convergenceDelta: Double,
            progress: Progress
        ) {
            self.scores = scores
            self.iterations = iterations
            self.convergenceDelta = convergenceDelta
            self.progress = progress
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeCount(scores.count)
            for score in scores { try score.encode(into: &writer) }
            writer.writeUInt32(iterations)
            writer.writeDouble(convergenceDelta)
            try progress.encode(into: &writer)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let count = try reader.readCount()
            var scores: [Score] = []
            scores.reserveCapacity(count)
            for _ in 0..<count { scores.append(try Score(from: &reader)) }
            self.init(
                scores: scores,
                iterations: try reader.readUInt32(),
                convergenceDelta: try reader.readDouble(),
                progress: try Progress(from: &reader)
            )
        }
    }

    public struct CommunityAssignment: DatabaseWireValue, Hashable {
        public let vertex: Term
        public let community: Term

        public init(vertex: Term, community: Term) {
            self.vertex = vertex
            self.community = community
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try vertex.encode(into: &writer)
            try community.encode(into: &writer)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                vertex: try Term(from: &reader),
                community: try Term(from: &reader)
            )
        }
    }

    public struct CommunityPage: DatabaseWireValue, Hashable {
        public let assignments: [CommunityAssignment]
        public let iterations: UInt32
        public let modularity: Double?
        public let progress: Progress

        public init(
            assignments: [CommunityAssignment],
            iterations: UInt32,
            modularity: Double? = nil,
            progress: Progress
        ) {
            self.assignments = assignments
            self.iterations = iterations
            self.modularity = modularity
            self.progress = progress
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeCount(assignments.count)
            for assignment in assignments { try assignment.encode(into: &writer) }
            writer.writeUInt32(iterations)
            writer.writeBool(modularity != nil)
            if let modularity { writer.writeDouble(modularity) }
            try progress.encode(into: &writer)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let count = try reader.readCount()
            var assignments: [CommunityAssignment] = []
            assignments.reserveCapacity(count)
            for _ in 0..<count {
                assignments.append(try CommunityAssignment(from: &reader))
            }
            let iterations = try reader.readUInt32()
            let modularity = try reader.readBool() ? try reader.readDouble() : nil
            self.init(
                assignments: assignments,
                iterations: iterations,
                modularity: modularity,
                progress: try Progress(from: &reader)
            )
        }
    }

    public struct DirectedEdge: DatabaseWireValue, Hashable {
        public let source: Term
        public let target: Term

        public init(source: Term, target: Term) {
            self.source = source
            self.target = target
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try source.encode(into: &writer)
            try target.encode(into: &writer)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                source: try Term(from: &reader),
                target: try Term(from: &reader)
            )
        }
    }

    public struct CyclePage: DatabaseWireValue, Hashable {
        public let cycles: [[Term]]
        public let backEdges: [DirectedEdge]
        public let nodesExplored: UInt64
        public let progress: Progress

        public init(
            cycles: [[Term]],
            backEdges: [DirectedEdge],
            nodesExplored: UInt64,
            progress: Progress
        ) {
            self.cycles = cycles
            self.backEdges = backEdges
            self.nodesExplored = nodesExplored
            self.progress = progress
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeCount(cycles.count)
            for cycle in cycles { try PathResult.encodeTerms(cycle, into: &writer) }
            try writer.writeCount(backEdges.count)
            for edge in backEdges { try edge.encode(into: &writer) }
            writer.writeUInt64(nodesExplored)
            try progress.encode(into: &writer)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let cycleCount = try reader.readCount()
            var cycles: [[Term]] = []
            cycles.reserveCapacity(cycleCount)
            for _ in 0..<cycleCount {
                cycles.append(try PathResult.decodeTerms(from: &reader))
            }
            let edgeCount = try reader.readCount()
            var backEdges: [DirectedEdge] = []
            backEdges.reserveCapacity(edgeCount)
            for _ in 0..<edgeCount {
                backEdges.append(try DirectedEdge(from: &reader))
            }
            self.init(
                cycles: cycles,
                backEdges: backEdges,
                nodesExplored: try reader.readUInt64(),
                progress: try Progress(from: &reader)
            )
        }
    }

    public struct ComponentPage: DatabaseWireValue, Hashable {
        public let components: [[Term]]
        public let nodesExplored: UInt64
        public let progress: Progress

        public init(
            components: [[Term]],
            nodesExplored: UInt64,
            progress: Progress
        ) {
            self.components = components
            self.nodesExplored = nodesExplored
            self.progress = progress
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeCount(components.count)
            for component in components {
                try PathResult.encodeTerms(component, into: &writer)
            }
            writer.writeUInt64(nodesExplored)
            try progress.encode(into: &writer)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let count = try reader.readCount()
            var components: [[Term]] = []
            components.reserveCapacity(count)
            for _ in 0..<count {
                components.append(try PathResult.decodeTerms(from: &reader))
            }
            self.init(
                components: components,
                nodesExplored: try reader.readUInt64(),
                progress: try Progress(from: &reader)
            )
        }
    }

    public struct TopologicalResult: DatabaseWireValue, Hashable {
        public let order: [Term]?
        public let cyclicNodes: [Term]
        public let totalNodes: UInt64
        public let progress: Progress

        public init(
            order: [Term]?,
            cyclicNodes: [Term],
            totalNodes: UInt64,
            progress: Progress
        ) {
            self.order = order
            self.cyclicNodes = cyclicNodes
            self.totalNodes = totalNodes
            self.progress = progress
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeBool(order != nil)
            if let order { try PathResult.encodeTerms(order, into: &writer) }
            try PathResult.encodeTerms(cyclicNodes, into: &writer)
            writer.writeUInt64(totalNodes)
            try progress.encode(into: &writer)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let order = try reader.readBool()
                ? try PathResult.decodeTerms(from: &reader)
                : nil
            self.init(
                order: order,
                cyclicNodes: try PathResult.decodeTerms(from: &reader),
                totalNodes: try reader.readUInt64(),
                progress: try Progress(from: &reader)
            )
        }
    }

    public enum Response: DatabaseWireValue, Hashable {
        case path(PathResult)
        case ranking(RankingPage)
        case communities(CommunityPage)
        case cycles(CyclePage)
        case components(ComponentPage)
        case topologicalOrder(TopologicalResult)

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .path(let result):
                writer.writeUInt8(1)
                try result.encode(into: &writer)
            case .ranking(let result):
                writer.writeUInt8(2)
                try result.encode(into: &writer)
            case .communities(let result):
                writer.writeUInt8(3)
                try result.encode(into: &writer)
            case .cycles(let result):
                writer.writeUInt8(4)
                try result.encode(into: &writer)
            case .components(let result):
                writer.writeUInt8(5)
                try result.encode(into: &writer)
            case .topologicalOrder(let result):
                writer.writeUInt8(6)
                try result.encode(into: &writer)
            }
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1: self = .path(try PathResult(from: &reader))
            case 2: self = .ranking(try RankingPage(from: &reader))
            case 3: self = .communities(try CommunityPage(from: &reader))
            case 4: self = .cycles(try CyclePage(from: &reader))
            case 5: self = .components(try ComponentPage(from: &reader))
            case 6: self = .topologicalOrder(try TopologicalResult(from: &reader))
            case let tag: throw .invalidResultPayload(tag)
            }
        }
    }
}

private extension GraphAlgorithmOperation.PathResult {
    static func encodeTerms(
        _ values: [GraphAlgorithmOperation.Term],
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeCount(values.count)
        for value in values { try value.encode(into: &writer) }
    }

    static func decodeTerms(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> [GraphAlgorithmOperation.Term] {
        let count = try reader.readCount()
        var values: [GraphAlgorithmOperation.Term] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            values.append(try GraphAlgorithmOperation.Term(from: &reader))
        }
        return values
    }
}
