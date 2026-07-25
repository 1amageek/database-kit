import DatabaseKit
import DatabaseTypes

public enum OntologyExecuteOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.ontologyExecute

    public enum ReasoningProfile: UInt8, Sendable, Hashable {
        case rdfs = 1
        case owlRL = 2

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

    public enum HierarchyDirection: UInt8, Sendable, Hashable {
        case ancestors = 1
        case descendants = 2

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

    public enum HierarchyResourceKind: UInt8, Sendable, Hashable {
        case `class` = 1
        case objectProperty = 2
        case dataProperty = 3

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

    public struct Document: WireValue, Hashable {
        public let ontology: String
        public let imports: [String]
        public let axioms: [RDFQuad]

        public init(
            ontology: String,
            imports: [String] = [],
            axioms: [RDFQuad]
        ) {
            self.ontology = ontology
            self.imports = imports
            self.axioms = axioms
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeString(ontology)
            try writer.writeCount(imports.count)
            for value in imports { try writer.writeString(value) }
            try writer.writeCount(axioms.count)
            for axiom in axioms { try axiom.encode(into: &writer) }
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let ontology = try reader.readString()
            let importCount = try reader.readCount()
            var imports: [String] = []
            imports.reserveCapacity(importCount)
            for _ in 0..<importCount { imports.append(try reader.readString()) }
            let axiomCount = try reader.readCount()
            var axioms: [RDFQuad] = []
            axioms.reserveCapacity(axiomCount)
            for _ in 0..<axiomCount {
                axioms.append(try RDFQuad(from: &reader))
            }
            self.init(ontology: ontology, imports: imports, axioms: axioms)
        }
    }

    public enum Invocation: Sendable, Hashable {
        case describe(ontology: String)
        case upsert(document: Document, expectedRevision: UInt64?)
        case delete(ontology: String, expectedRevision: UInt64?)
        case reason(ontology: String, profile: ReasoningProfile)
        case hierarchy(
            ontology: String,
            resource: String,
            resourceKind: HierarchyResourceKind,
            direction: HierarchyDirection,
            maximumDepth: UInt32
        )
        case validateSchema(ontology: String)

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .describe(let ontology):
                writer.writeUInt8(1)
                try writer.writeString(ontology)
            case .upsert(let document, let expectedRevision):
                writer.writeUInt8(2)
                try document.encode(into: &writer)
                Self.encodeRevision(expectedRevision, into: &writer)
            case .delete(let ontology, let expectedRevision):
                writer.writeUInt8(3)
                try writer.writeString(ontology)
                Self.encodeRevision(expectedRevision, into: &writer)
            case .reason(let ontology, let profile):
                writer.writeUInt8(4)
                try writer.writeString(ontology)
                writer.writeUInt8(profile.rawValue)
            case .hierarchy(
                let ontology,
                let resource,
                let resourceKind,
                let direction,
                let maximumDepth
            ):
                writer.writeUInt8(5)
                try writer.writeString(ontology)
                try writer.writeString(resource)
                writer.writeUInt8(resourceKind.rawValue)
                writer.writeUInt8(direction.rawValue)
                writer.writeUInt32(maximumDepth)
            case .validateSchema(let ontology):
                writer.writeUInt8(6)
                try writer.writeString(ontology)
            }
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1:
                self = .describe(ontology: try reader.readString())
            case 2:
                self = .upsert(
                    document: try Document(from: &reader),
                    expectedRevision: try Self.decodeRevision(from: &reader)
                )
            case 3:
                self = .delete(
                    ontology: try reader.readString(),
                    expectedRevision: try Self.decodeRevision(from: &reader)
                )
            case 4:
                self = .reason(
                    ontology: try reader.readString(),
                    profile: try ReasoningProfile(from: &reader)
                )
            case 5:
                self = .hierarchy(
                    ontology: try reader.readString(),
                    resource: try reader.readString(),
                    resourceKind: try HierarchyResourceKind(from: &reader),
                    direction: try HierarchyDirection(from: &reader),
                    maximumDepth: try reader.readUInt32()
                )
            case 6:
                self = .validateSchema(ontology: try reader.readString())
            case let tag:
                throw .invalidValueTag(tag)
            }
        }

        private static func encodeRevision(
            _ revision: UInt64?,
            into writer: inout DatabaseWireWriter
        ) {
            writer.writeBool(revision != nil)
            if let revision { writer.writeUInt64(revision) }
        }

        private static func decodeRevision(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> UInt64? {
            try reader.readBool() ? try reader.readUInt64() : nil
        }
    }

    public struct Request: WireValue, Hashable {
        public let invocation: Invocation
        public let page: QueryExecuteOperation.Page
        public let budget: ExecutionBudget

        public init(
            invocation: Invocation,
            page: QueryExecuteOperation.Page = QueryExecuteOperation.Page(),
            budget: ExecutionBudget = ExecutionBudget()
        ) {
            self.invocation = invocation
            self.page = page
            self.budget = budget
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try invocation.encode(into: &writer)
            try page.encode(into: &writer)
            try budget.encode(into: &writer)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                invocation: try Invocation(from: &reader),
                page: try QueryExecuteOperation.Page(from: &reader),
                budget: try ExecutionBudget(from: &reader)
            )
        }
    }

    public struct DocumentPage: WireValue {
        private let importElements: RetainedResultElements<String>
        private let axiomElements: RetainedResultElements<RDFQuad>

        public let ontology: String
        public let revision: UInt64
        public var importCount: Int { importElements.count }
        public var axiomCount: Int { axiomElements.count }
        public let continuation: ByteString?

        public init(
            ontology: String,
            revision: UInt64,
            imports: [String],
            axioms: [RDFQuad],
            continuation: ByteString? = nil
        ) {
            self.ontology = ontology
            self.revision = revision
            self.importElements = RetainedResultElements(imports)
            self.axiomElements = RetainedResultElements(axioms)
            self.continuation = continuation
        }

        public func makeImportIterator() -> ResultIterator<String> {
            importElements.makeIterator(
                decodeElement: {
                    reader throws(DatabaseWireError) in
                    try reader.readString()
                }
            )
        }

        public func makeAxiomIterator() -> ResultIterator<RDFQuad> {
            axiomElements.makeIterator(decodeElement: RDFQuad.init(from:))
        }

        public func materializedImports(
            maximumCount: Int
        ) throws(DatabaseWireError) -> [String] {
            try importElements.materialized(
                maximumCount: maximumCount,
                decodeElement: {
                    reader throws(DatabaseWireError) in
                    try reader.readString()
                }
            )
        }

        public func materializedAxioms(
            maximumCount: Int
        ) throws(DatabaseWireError) -> [RDFQuad] {
            try axiomElements.materialized(
                maximumCount: maximumCount,
                decodeElement: RDFQuad.init(from:)
            )
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeString(ontology)
            writer.writeUInt64(revision)
            try Self.encodeStrings(importElements, into: &writer)
            try Self.encodeQuads(axiomElements, into: &writer)
            try writer.writeOptionalBytes(continuation)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.ontology = try reader.readString()
            self.revision = try reader.readUInt64()
            self.importElements = try Self.decodeStrings(from: &reader)
            self.axiomElements = try Self.decodeQuads(from: &reader)
            self.continuation = try reader.readOptionalBytes()
        }

        var retainedEncodedAxioms: ByteString? {
            axiomElements.retainedBytes
        }

        private static func encodeStrings(
            _ elements: RetainedResultElements<String>,
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try elements.encode(
                into: &writer,
                encodeElement: {
                    (
                        value: String,
                        writer: inout DatabaseWireWriter
                    ) throws(DatabaseWireError) in
                    try writer.writeString(value)
                },
                validateElement: {
                    reader throws(DatabaseWireError) in
                    _ = try reader.readValidatedUTF8Bytes()
                }
            )
        }

        private static func decodeStrings(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> RetainedResultElements<String> {
            try RetainedResultElements(
                from: &reader,
                validateElement: {
                    reader throws(DatabaseWireError) in
                    _ = try reader.readValidatedUTF8Bytes()
                }
            )
        }

        fileprivate static func encodeQuads(
            _ elements: RetainedResultElements<RDFQuad>,
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try elements.encode(
                into: &writer,
                encodeElement: {
                    (
                        quad: RDFQuad,
                        writer: inout DatabaseWireWriter
                    ) throws(DatabaseWireError) in
                    try quad.encode(into: &writer)
                },
                validateElement: RDFQuad.validateWireRepresentation(from:)
            )
        }

        fileprivate static func decodeQuads(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> RetainedResultElements<RDFQuad> {
            try RetainedResultElements(
                from: &reader,
                validateElement: RDFQuad.validateWireRepresentation(from:)
            )
        }
    }

    public struct InferencePage: WireValue {
        private let axiomElements: RetainedResultElements<RDFQuad>

        public var inferredAxiomCount: Int { axiomElements.count }
        public let isComplete: Bool
        public let continuation: ByteString?

        public init(
            inferredAxioms: [RDFQuad],
            isComplete: Bool,
            continuation: ByteString? = nil
        ) {
            self.axiomElements = RetainedResultElements(inferredAxioms)
            self.isComplete = isComplete
            self.continuation = continuation
        }

        public func makeInferredAxiomIterator()
            -> ResultIterator<RDFQuad> {
            axiomElements.makeIterator(decodeElement: RDFQuad.init(from:))
        }

        public func materializedInferredAxioms(
            maximumCount: Int
        ) throws(DatabaseWireError) -> [RDFQuad] {
            try axiomElements.materialized(
                maximumCount: maximumCount,
                decodeElement: RDFQuad.init(from:)
            )
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try DocumentPage.encodeQuads(axiomElements, into: &writer)
            writer.writeBool(isComplete)
            try writer.writeOptionalBytes(continuation)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.axiomElements = try DocumentPage.decodeQuads(from: &reader)
            self.isComplete = try reader.readBool()
            self.continuation = try reader.readOptionalBytes()
        }
    }

    public struct HierarchyEntry: WireValue, Hashable {
        public let resource: String
        public let depth: UInt32

        public init(resource: String, depth: UInt32) {
            self.resource = resource
            self.depth = depth
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeString(resource)
            writer.writeUInt32(depth)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                resource: try reader.readString(),
                depth: try reader.readUInt32()
            )
        }

        static func validateWireRepresentation(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            _ = try reader.readValidatedUTF8Bytes()
            _ = try reader.readUInt32()
        }
    }

    public struct HierarchyPage: WireValue {
        private let entryElements: RetainedResultElements<HierarchyEntry>

        public var entryCount: Int { entryElements.count }
        public let continuation: ByteString?

        public init(entries: [HierarchyEntry], continuation: ByteString? = nil) {
            self.entryElements = RetainedResultElements(entries)
            self.continuation = continuation
        }

        public func makeEntryIterator() -> ResultIterator<HierarchyEntry> {
            entryElements.makeIterator(
                decodeElement: HierarchyEntry.init(from:)
            )
        }

        public func materializedEntries(
            maximumCount: Int
        ) throws(DatabaseWireError) -> [HierarchyEntry] {
            try entryElements.materialized(
                maximumCount: maximumCount,
                decodeElement: HierarchyEntry.init(from:)
            )
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try entryElements.encode(
                into: &writer,
                encodeElement: {
                    (
                        entry: HierarchyEntry,
                        writer: inout DatabaseWireWriter
                    ) throws(DatabaseWireError) in
                    try entry.encode(into: &writer)
                },
                validateElement:
                    HierarchyEntry.validateWireRepresentation(from:)
            )
            try writer.writeOptionalBytes(continuation)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.entryElements = try RetainedResultElements(
                from: &reader,
                validateElement:
                    HierarchyEntry.validateWireRepresentation(from:)
            )
            self.continuation = try reader.readOptionalBytes()
        }
    }

    public enum Response: WireValue {
        case document(DocumentPage)
        case mutation(RevisionMutationResult)
        case inference(InferencePage)
        case hierarchy(HierarchyPage)
        case validation(ValidationReport)

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .document(let value):
                writer.writeUInt8(1)
                try value.encode(into: &writer)
            case .mutation(let value):
                writer.writeUInt8(2)
                try value.encode(into: &writer)
            case .inference(let value):
                writer.writeUInt8(3)
                try value.encode(into: &writer)
            case .hierarchy(let value):
                writer.writeUInt8(4)
                try value.encode(into: &writer)
            case .validation(let value):
                writer.writeUInt8(5)
                try value.encode(into: &writer)
            }
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 1: self = .document(try DocumentPage(from: &reader))
            case 2: self = .mutation(try RevisionMutationResult(from: &reader))
            case 3: self = .inference(try InferencePage(from: &reader))
            case 4: self = .hierarchy(try HierarchyPage(from: &reader))
            case 5: self = .validation(try ValidationReport(from: &reader))
            case let tag: throw .invalidResultPayload(tag)
            }
        }
    }
}
