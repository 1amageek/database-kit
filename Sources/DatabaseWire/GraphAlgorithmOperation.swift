import DatabaseKit
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

    public struct Source: WireValue, Hashable {
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

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeString(index)
            try partitions.encode(into: &writer)
            try graph.encode(into: &writer)
            writer.writeBool(edgeLabel != nil)
            if let edgeLabel { try edgeLabel.encode(into: &writer) }
        }

        init(
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

    public struct Progress: WireValue, Hashable {
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

        func encode(
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

        init(
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

    public struct Page: WireValue, Hashable {
        public let limit: UInt32
        public let continuation: ByteString?

        public init(limit: UInt32 = 1_000, continuation: ByteString? = nil) {
            self.limit = limit
            self.continuation = continuation
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeUInt32(limit)
            try writer.writeOptionalBytes(continuation)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                limit: try reader.readUInt32(),
                continuation: try reader.readOptionalBytes()
            )
        }
    }

    public struct Request: WireValue, Hashable {
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

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try source.encode(into: &writer)
            try invocation.encode(into: &writer)
            try page.encode(into: &writer)
            try budget.encode(into: &writer)
        }

        init(
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

    public struct PathResult: WireValue {
        private let nodeElements: RetainedResultElements<Term>
        private let edgeLabelElements: RetainedResultElements<Term>
        private let weightElements: RetainedResultElements<Double>

        public let found: Bool
        public var nodeCount: Int { nodeElements.count }
        public var edgeLabelCount: Int { edgeLabelElements.count }
        public var weightCount: Int { weightElements.count }
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
            self.nodeElements = RetainedResultElements(nodes)
            self.edgeLabelElements = RetainedResultElements(edgeLabels)
            self.weightElements = RetainedResultElements(weights)
            self.totalWeight = totalWeight
            self.nodesExplored = nodesExplored
            self.durationNanoseconds = durationNanoseconds
            self.progress = progress
        }

        public func makeNodeIterator() -> ResultIterator<Term> {
            nodeElements.makeIterator(decodeElement: Term.init(from:))
        }

        public func makeEdgeLabelIterator() -> ResultIterator<Term> {
            edgeLabelElements.makeIterator(decodeElement: Term.init(from:))
        }

        public func makeWeightIterator() -> ResultIterator<Double> {
            weightElements.makeIterator(
                decodeElement: { reader throws(DatabaseWireError) in
                    try reader.readDouble()
                }
            )
        }

        public func materializedNodes(
            maximumCount: Int
        ) throws(DatabaseWireError) -> [Term] {
            try nodeElements.materialized(
                maximumCount: maximumCount,
                decodeElement: Term.init(from:)
            )
        }

        public func materializedEdgeLabels(
            maximumCount: Int
        ) throws(DatabaseWireError) -> [Term] {
            try edgeLabelElements.materialized(
                maximumCount: maximumCount,
                decodeElement: Term.init(from:)
            )
        }

        public func materializedWeights(
            maximumCount: Int
        ) throws(DatabaseWireError) -> [Double] {
            try weightElements.materialized(
                maximumCount: maximumCount,
                decodeElement: { reader throws(DatabaseWireError) in
                    try reader.readDouble()
                }
            )
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try validate()
            writer.writeBool(found)
            try Self.encodeTerms(nodeElements, into: &writer)
            try Self.encodeTerms(edgeLabelElements, into: &writer)
            try weightElements.encode(
                into: &writer,
                encodeElement: {
                    (
                        weight: Double,
                        writer: inout DatabaseWireWriter
                    ) throws(DatabaseWireError) in
                    writer.writeDouble(weight)
                },
                validateElement: {
                    reader throws(DatabaseWireError) in
                    _ = try reader.readDouble()
                }
            )
            writer.writeBool(totalWeight != nil)
            if let totalWeight { writer.writeDouble(totalWeight) }
            writer.writeUInt64(nodesExplored)
            writer.writeUInt64(durationNanoseconds)
            try progress.encode(into: &writer)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.found = try reader.readBool()
            self.nodeElements = try Self.decodeTerms(from: &reader)
            self.edgeLabelElements = try Self.decodeTerms(from: &reader)
            self.weightElements = try RetainedResultElements(
                from: &reader,
                validateElement: {
                    reader throws(DatabaseWireError) in
                    _ = try reader.readDouble()
                }
            )
            self.totalWeight =
                try reader.readBool() ? try reader.readDouble() : nil
            self.nodesExplored = try reader.readUInt64()
            self.durationNanoseconds = try reader.readUInt64()
            self.progress = try Progress(from: &reader)
            try validate()
        }

        private func validate() throws(DatabaseWireError) {
            guard found ? nodeCount > 0 : nodeCount == 0 else {
                throw .invalidGraphResult
            }
            guard !found || progress.algorithmComplete else {
                throw .invalidGraphResult
            }
            guard edgeLabelCount == 0 || edgeLabelCount + 1 == nodeCount else {
                throw .invalidGraphResult
            }
            guard weightCount == 0 || weightCount + 1 == nodeCount else {
                throw .invalidGraphResult
            }
            guard totalWeight == nil || found else {
                throw .invalidGraphResult
            }
        }

        var retainedEncodedNodes: ByteString? {
            nodeElements.retainedBytes
        }
    }

    public struct Score: WireValue, Hashable {
        public let vertex: Term
        public let score: Double

        public init(vertex: Term, score: Double) {
            self.vertex = vertex
            self.score = score
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try vertex.encode(into: &writer)
            writer.writeDouble(score)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                vertex: try Term(from: &reader),
                score: try reader.readDouble()
            )
        }

        static func validateWireRepresentation(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            try Term.validateWireRepresentation(from: &reader)
            _ = try reader.readDouble()
        }
    }

    public struct RankingPage: WireValue {
        private let scoreElements: RetainedResultElements<Score>

        public var scoreCount: Int { scoreElements.count }
        public let iterations: UInt32
        public let convergenceDelta: Double
        public let progress: Progress

        public init(
            scores: [Score],
            iterations: UInt32,
            convergenceDelta: Double,
            progress: Progress
        ) {
            self.scoreElements = RetainedResultElements(scores)
            self.iterations = iterations
            self.convergenceDelta = convergenceDelta
            self.progress = progress
        }

        public func makeScoreIterator() -> ResultIterator<Score> {
            scoreElements.makeIterator(decodeElement: Score.init(from:))
        }

        public func materializedScores(
            maximumCount: Int
        ) throws(DatabaseWireError) -> [Score] {
            try scoreElements.materialized(
                maximumCount: maximumCount,
                decodeElement: Score.init(from:)
            )
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try scoreElements.encode(
                into: &writer,
                encodeElement: {
                    (
                        score: Score,
                        writer: inout DatabaseWireWriter
                    ) throws(DatabaseWireError) in
                    try score.encode(into: &writer)
                },
                validateElement: Score.validateWireRepresentation(from:)
            )
            writer.writeUInt32(iterations)
            writer.writeDouble(convergenceDelta)
            try progress.encode(into: &writer)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.scoreElements = try RetainedResultElements(
                from: &reader,
                validateElement: Score.validateWireRepresentation(from:)
            )
            self.iterations = try reader.readUInt32()
            self.convergenceDelta = try reader.readDouble()
            self.progress = try Progress(from: &reader)
        }

        var retainedEncodedScores: ByteString? {
            scoreElements.retainedBytes
        }
    }

    public struct CommunityAssignment: WireValue, Hashable {
        public let vertex: Term
        public let community: Term

        public init(vertex: Term, community: Term) {
            self.vertex = vertex
            self.community = community
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try vertex.encode(into: &writer)
            try community.encode(into: &writer)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                vertex: try Term(from: &reader),
                community: try Term(from: &reader)
            )
        }

        static func validateWireRepresentation(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            try Term.validateWireRepresentation(from: &reader)
            try Term.validateWireRepresentation(from: &reader)
        }
    }

    public struct CommunityPage: WireValue {
        private let assignmentElements:
            RetainedResultElements<CommunityAssignment>

        public var assignmentCount: Int { assignmentElements.count }
        public let iterations: UInt32
        public let modularity: Double?
        public let progress: Progress

        public init(
            assignments: [CommunityAssignment],
            iterations: UInt32,
            modularity: Double? = nil,
            progress: Progress
        ) {
            self.assignmentElements = RetainedResultElements(assignments)
            self.iterations = iterations
            self.modularity = modularity
            self.progress = progress
        }

        public func makeAssignmentIterator()
            -> ResultIterator<CommunityAssignment> {
            assignmentElements.makeIterator(
                decodeElement: CommunityAssignment.init(from:)
            )
        }

        public func materializedAssignments(
            maximumCount: Int
        ) throws(DatabaseWireError) -> [CommunityAssignment] {
            try assignmentElements.materialized(
                maximumCount: maximumCount,
                decodeElement: CommunityAssignment.init(from:)
            )
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try assignmentElements.encode(
                into: &writer,
                encodeElement: {
                    (
                        assignment: CommunityAssignment,
                        writer: inout DatabaseWireWriter
                    ) throws(DatabaseWireError) in
                    try assignment.encode(into: &writer)
                },
                validateElement:
                    CommunityAssignment.validateWireRepresentation(from:)
            )
            writer.writeUInt32(iterations)
            writer.writeBool(modularity != nil)
            if let modularity { writer.writeDouble(modularity) }
            try progress.encode(into: &writer)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.assignmentElements = try RetainedResultElements(
                from: &reader,
                validateElement:
                    CommunityAssignment.validateWireRepresentation(from:)
            )
            self.iterations = try reader.readUInt32()
            self.modularity =
                try reader.readBool() ? try reader.readDouble() : nil
            self.progress = try Progress(from: &reader)
        }

        var retainedEncodedAssignments: ByteString? {
            assignmentElements.retainedBytes
        }
    }

    public struct DirectedEdge: WireValue, Hashable {
        public let source: Term
        public let target: Term

        public init(source: Term, target: Term) {
            self.source = source
            self.target = target
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try source.encode(into: &writer)
            try target.encode(into: &writer)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                source: try Term(from: &reader),
                target: try Term(from: &reader)
            )
        }

        static func validateWireRepresentation(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            try Term.validateWireRepresentation(from: &reader)
            try Term.validateWireRepresentation(from: &reader)
        }
    }

    public struct Cycle: WireValue {
        private let termElements: RetainedResultElements<Term>

        public var termCount: Int { termElements.count }

        public init(terms: [Term]) {
            self.termElements = RetainedResultElements(terms)
        }

        public func makeTermIterator() -> ResultIterator<Term> {
            termElements.makeIterator(decodeElement: Term.init(from:))
        }

        public func materializedTerms(
            maximumCount: Int
        ) throws(DatabaseWireError) -> [Term] {
            try termElements.materialized(
                maximumCount: maximumCount,
                decodeElement: Term.init(from:)
            )
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try PathResult.encodeTerms(termElements, into: &writer)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.termElements = try PathResult.decodeTerms(from: &reader)
        }

        static func validateWireRepresentation(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let count = try reader.readCount()
            for _ in 0..<count {
                try Term.validateWireRepresentation(from: &reader)
            }
        }

        var retainedEncodedTerms: ByteString? {
            termElements.retainedBytes
        }
    }

    public struct CyclePage: WireValue {
        private let cycleElements: RetainedResultElements<Cycle>
        private let backEdgeElements: RetainedResultElements<DirectedEdge>

        public var cycleCount: Int { cycleElements.count }
        public var backEdgeCount: Int { backEdgeElements.count }
        public let nodesExplored: UInt64
        public let progress: Progress

        public init(
            cycles: [Cycle],
            backEdges: [DirectedEdge],
            nodesExplored: UInt64,
            progress: Progress
        ) {
            self.cycleElements = RetainedResultElements(cycles)
            self.backEdgeElements = RetainedResultElements(backEdges)
            self.nodesExplored = nodesExplored
            self.progress = progress
        }

        public func makeCycleIterator() -> ResultIterator<Cycle> {
            cycleElements.makeIterator(decodeElement: Cycle.init(from:))
        }

        public func makeBackEdgeIterator() -> ResultIterator<DirectedEdge> {
            backEdgeElements.makeIterator(
                decodeElement: DirectedEdge.init(from:)
            )
        }

        public func materializedCycles(
            maximumCount: Int
        ) throws(DatabaseWireError) -> [Cycle] {
            try cycleElements.materialized(
                maximumCount: maximumCount,
                decodeElement: Cycle.init(from:)
            )
        }

        public func materializedBackEdges(
            maximumCount: Int
        ) throws(DatabaseWireError) -> [DirectedEdge] {
            try backEdgeElements.materialized(
                maximumCount: maximumCount,
                decodeElement: DirectedEdge.init(from:)
            )
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try cycleElements.encode(
                into: &writer,
                encodeElement: {
                    (
                        cycle: Cycle,
                        writer: inout DatabaseWireWriter
                    ) throws(DatabaseWireError) in
                    try cycle.encode(into: &writer)
                },
                validateElement: Cycle.validateWireRepresentation(from:)
            )
            try backEdgeElements.encode(
                into: &writer,
                encodeElement: {
                    (
                        edge: DirectedEdge,
                        writer: inout DatabaseWireWriter
                    ) throws(DatabaseWireError) in
                    try edge.encode(into: &writer)
                },
                validateElement:
                    DirectedEdge.validateWireRepresentation(from:)
            )
            writer.writeUInt64(nodesExplored)
            try progress.encode(into: &writer)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.cycleElements = try RetainedResultElements(
                from: &reader,
                validateElement: Cycle.validateWireRepresentation(from:)
            )
            self.backEdgeElements = try RetainedResultElements(
                from: &reader,
                validateElement:
                    DirectedEdge.validateWireRepresentation(from:)
            )
            self.nodesExplored = try reader.readUInt64()
            self.progress = try Progress(from: &reader)
        }

        var retainedEncodedCycles: ByteString? {
            cycleElements.retainedBytes
        }
    }

    public struct Component: WireValue {
        private let termElements: RetainedResultElements<Term>

        public var termCount: Int { termElements.count }

        public init(terms: [Term]) {
            self.termElements = RetainedResultElements(terms)
        }

        public func makeTermIterator() -> ResultIterator<Term> {
            termElements.makeIterator(decodeElement: Term.init(from:))
        }

        public func materializedTerms(
            maximumCount: Int
        ) throws(DatabaseWireError) -> [Term] {
            try termElements.materialized(
                maximumCount: maximumCount,
                decodeElement: Term.init(from:)
            )
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try PathResult.encodeTerms(termElements, into: &writer)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.termElements = try PathResult.decodeTerms(from: &reader)
        }

        static func validateWireRepresentation(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            try Cycle.validateWireRepresentation(from: &reader)
        }
    }

    public struct ComponentPage: WireValue {
        private let componentElements: RetainedResultElements<Component>

        public var componentCount: Int { componentElements.count }
        public let nodesExplored: UInt64
        public let progress: Progress

        public init(
            components: [Component],
            nodesExplored: UInt64,
            progress: Progress
        ) {
            self.componentElements = RetainedResultElements(components)
            self.nodesExplored = nodesExplored
            self.progress = progress
        }

        public func makeComponentIterator() -> ResultIterator<Component> {
            componentElements.makeIterator(
                decodeElement: Component.init(from:)
            )
        }

        public func materializedComponents(
            maximumCount: Int
        ) throws(DatabaseWireError) -> [Component] {
            try componentElements.materialized(
                maximumCount: maximumCount,
                decodeElement: Component.init(from:)
            )
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try componentElements.encode(
                into: &writer,
                encodeElement: {
                    (
                        component: Component,
                        writer: inout DatabaseWireWriter
                    ) throws(DatabaseWireError) in
                    try component.encode(into: &writer)
                },
                validateElement:
                    Component.validateWireRepresentation(from:)
            )
            writer.writeUInt64(nodesExplored)
            try progress.encode(into: &writer)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.componentElements = try RetainedResultElements(
                from: &reader,
                validateElement:
                    Component.validateWireRepresentation(from:)
            )
            self.nodesExplored = try reader.readUInt64()
            self.progress = try Progress(from: &reader)
        }
    }

    public struct TopologicalResult: WireValue {
        private let orderElements: RetainedResultElements<Term>?
        private let cyclicNodeElements: RetainedResultElements<Term>

        public var orderCount: Int? { orderElements?.count }
        public var cyclicNodeCount: Int { cyclicNodeElements.count }
        public let totalNodes: UInt64
        public let progress: Progress

        public init(
            order: [Term]?,
            cyclicNodes: [Term],
            totalNodes: UInt64,
            progress: Progress
        ) {
            self.orderElements = order.map(RetainedResultElements.init)
            self.cyclicNodeElements = RetainedResultElements(cyclicNodes)
            self.totalNodes = totalNodes
            self.progress = progress
        }

        public func makeOrderIterator() -> ResultIterator<Term>? {
            orderElements?.makeIterator(decodeElement: Term.init(from:))
        }

        public func makeCyclicNodeIterator() -> ResultIterator<Term> {
            cyclicNodeElements.makeIterator(decodeElement: Term.init(from:))
        }

        public func materializedOrder(
            maximumCount: Int
        ) throws(DatabaseWireError) -> [Term]? {
            guard let orderElements else {
                return nil
            }
            return try orderElements.materialized(
                maximumCount: maximumCount,
                decodeElement: Term.init(from:)
            )
        }

        public func materializedCyclicNodes(
            maximumCount: Int
        ) throws(DatabaseWireError) -> [Term] {
            try cyclicNodeElements.materialized(
                maximumCount: maximumCount,
                decodeElement: Term.init(from:)
            )
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeBool(orderElements != nil)
            if let orderElements {
                try PathResult.encodeTerms(orderElements, into: &writer)
            }
            try PathResult.encodeTerms(cyclicNodeElements, into: &writer)
            writer.writeUInt64(totalNodes)
            try progress.encode(into: &writer)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.orderElements = try reader.readBool()
                ? try PathResult.decodeTerms(from: &reader)
                : nil
            self.cyclicNodeElements =
                try PathResult.decodeTerms(from: &reader)
            self.totalNodes = try reader.readUInt64()
            self.progress = try Progress(from: &reader)
        }
    }

    public enum Response: WireValue {
        case path(PathResult)
        case ranking(RankingPage)
        case communities(CommunityPage)
        case cycles(CyclePage)
        case components(ComponentPage)
        case topologicalOrder(TopologicalResult)

        func encode(
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

        init(
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
        _ values: RetainedResultElements<GraphAlgorithmOperation.Term>,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try values.encode(
            into: &writer,
            encodeElement: {
                (
                    value: GraphAlgorithmOperation.Term,
                    writer: inout DatabaseWireWriter
                ) throws(DatabaseWireError) in
                try value.encode(into: &writer)
            },
            validateElement:
                GraphAlgorithmOperation.Term
                    .validateWireRepresentation(from:)
        )
    }

    static func decodeTerms(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError)
        -> RetainedResultElements<GraphAlgorithmOperation.Term> {
        try RetainedResultElements(
            from: &reader,
            validateElement:
                GraphAlgorithmOperation.Term
                    .validateWireRepresentation(from:)
        )
    }
}
