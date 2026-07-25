import DatabaseKit
import DatabaseTypes

public struct ValidationReport: WireValue {
    public enum Severity: UInt8, Sendable, Hashable {
        case information = 1
        case warning = 2
        case violation = 3

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

    public struct Issue: WireValue, Hashable {
        public let severity: Severity
        public let code: String
        public let messages: [String]
        public let focusNode: RDFTerm?
        public let path: SHACLPath?
        public let value: RDFTerm?
        public let sourceConstraintComponent: String?
        public let sourceShape: RDFTerm?
        public let details: FieldObject

        public init(
            severity: Severity,
            code: String,
            messages: [String] = [],
            focusNode: RDFTerm? = nil,
            path: SHACLPath? = nil,
            value: RDFTerm? = nil,
            sourceConstraintComponent: String? = nil,
            sourceShape: RDFTerm? = nil,
            details: FieldObject = FieldObject()
        ) {
            self.severity = severity
            self.code = code
            self.messages = messages
            self.focusNode = focusNode
            self.path = path
            self.value = value
            self.sourceConstraintComponent = sourceConstraintComponent
            self.sourceShape = sourceShape
            self.details = details
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeUInt8(severity.rawValue)
            try writer.writeString(code)
            try writer.writeCount(messages.count)
            for message in messages { try writer.writeString(message) }
            try Self.encodeOptionalTerm(focusNode, into: &writer)
            try Self.encodeOptionalPath(path, into: &writer)
            try Self.encodeOptionalTerm(value, into: &writer)
            try writer.writeOptionalString(sourceConstraintComponent)
            try Self.encodeOptionalTerm(sourceShape, into: &writer)
            try details.encode(into: &writer)
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            let severity = try Severity(from: &reader)
            let code = try reader.readString()
            let messageCount = try reader.readCount()
            var messages: [String] = []
            messages.reserveCapacity(messageCount)
            for _ in 0..<messageCount { messages.append(try reader.readString()) }
            let focusNode = try Self.decodeOptionalTerm(from: &reader)
            let path = try Self.decodeOptionalPath(from: &reader)
            let value = try Self.decodeOptionalTerm(from: &reader)
            let sourceConstraintComponent = try reader.readOptionalString()
            let sourceShape = try Self.decodeOptionalTerm(from: &reader)
            self.init(
                severity: severity,
                code: code,
                messages: messages,
                focusNode: focusNode,
                path: path,
                value: value,
                sourceConstraintComponent: sourceConstraintComponent,
                sourceShape: sourceShape,
                details: try FieldObject(from: &reader)
            )
        }

        static func validateWireRepresentation(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            _ = try Severity(from: &reader)
            _ = try reader.readValidatedUTF8Bytes()
            let messageCount = try reader.readCount()
            for _ in 0..<messageCount {
                _ = try reader.readValidatedUTF8Bytes()
            }
            try validateOptionalTerm(from: &reader)
            if try reader.readBool() {
                try SHACLPath.validateWireRepresentation(from: &reader)
            }
            try validateOptionalTerm(from: &reader)
            if try reader.readBool() {
                _ = try reader.readValidatedUTF8Bytes()
            }
            try validateOptionalTerm(from: &reader)
            try FieldValueWireValidator.validateObject(from: &reader)
        }

        private static func encodeOptionalTerm(
            _ term: RDFTerm?,
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeBool(term != nil)
            if let term { try term.encode(into: &writer) }
        }

        private static func decodeOptionalTerm(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> RDFTerm? {
            try reader.readBool() ? try RDFTerm(from: &reader) : nil
        }

        private static func encodeOptionalPath(
            _ path: SHACLPath?,
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeBool(path != nil)
            if let path { try path.encode(into: &writer) }
        }

        private static func decodeOptionalPath(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> SHACLPath? {
            try reader.readBool() ? try SHACLPath(from: &reader) : nil
        }

        private static func validateOptionalTerm(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            if try reader.readBool() {
                try reader.validateCanonicalRDFTerm(role: .term)
            }
        }
    }

    private let issueElements: RetainedResultElements<Issue>

    public let conforms: Bool
    public var issueCount: Int { issueElements.count }
    public let continuation: ByteString?

    public init(
        conforms: Bool,
        issues: [Issue],
        continuation: ByteString? = nil
    ) {
        self.conforms = conforms
        self.issueElements = RetainedResultElements(issues)
        self.continuation = continuation
    }

    public func makeIssueIterator() -> ResultIterator<Issue> {
        issueElements.makeIterator(decodeElement: Issue.init(from:))
    }

    public func materializedIssues(
        maximumCount: Int
    ) throws(DatabaseWireError) -> [Issue] {
        try issueElements.materialized(
            maximumCount: maximumCount,
            decodeElement: Issue.init(from:)
        )
    }

    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeBool(conforms)
        try issueElements.encode(
            into: &writer,
            encodeElement: {
                (
                    issue: Issue,
                    writer: inout DatabaseWireWriter
                ) throws(DatabaseWireError) in
                try issue.encode(into: &writer)
            },
            validateElement: Issue.validateWireRepresentation(from:)
        )
        try writer.writeOptionalBytes(continuation)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.conforms = try reader.readBool()
        self.issueElements = try RetainedResultElements(
            from: &reader,
            validateElement: Issue.validateWireRepresentation(from:)
        )
        self.continuation = try reader.readOptionalBytes()
    }

    var retainedEncodedIssues: ByteString? {
        issueElements.retainedBytes
    }
}
