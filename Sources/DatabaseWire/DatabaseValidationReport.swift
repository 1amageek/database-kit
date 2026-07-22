public import DatabaseValue

public struct DatabaseValidationReport: DatabaseWireValue, Hashable {
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

    public struct Issue: DatabaseWireValue, Hashable {
        public let severity: Severity
        public let code: String
        public let messages: [String]
        public let focusNode: DatabaseRDFTerm?
        public let path: DatabaseSHACLPath?
        public let value: DatabaseRDFTerm?
        public let sourceConstraintComponent: String?
        public let sourceShape: DatabaseRDFTerm?
        public let details: [DatabaseObjectField]

        public init(
            severity: Severity,
            code: String,
            messages: [String] = [],
            focusNode: DatabaseRDFTerm? = nil,
            path: DatabaseSHACLPath? = nil,
            value: DatabaseRDFTerm? = nil,
            sourceConstraintComponent: String? = nil,
            sourceShape: DatabaseRDFTerm? = nil,
            details: [DatabaseObjectField] = []
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

        public func encode(
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
            try writer.writeCount(details.count)
            for detail in details { try detail.encode(into: &writer) }
        }

        public init(
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
            let count = try reader.readCount()
            var details: [DatabaseObjectField] = []
            details.reserveCapacity(count)
            for _ in 0..<count {
                details.append(try DatabaseObjectField(from: &reader))
            }
            self.init(
                severity: severity,
                code: code,
                messages: messages,
                focusNode: focusNode,
                path: path,
                value: value,
                sourceConstraintComponent: sourceConstraintComponent,
                sourceShape: sourceShape,
                details: details
            )
        }

        private static func encodeOptionalTerm(
            _ term: DatabaseRDFTerm?,
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeBool(term != nil)
            if let term { try term.encode(into: &writer) }
        }

        private static func decodeOptionalTerm(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> DatabaseRDFTerm? {
            try reader.readBool() ? try DatabaseRDFTerm(from: &reader) : nil
        }

        private static func encodeOptionalPath(
            _ path: DatabaseSHACLPath?,
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            writer.writeBool(path != nil)
            if let path { try path.encode(into: &writer) }
        }

        private static func decodeOptionalPath(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> DatabaseSHACLPath? {
            try reader.readBool() ? try DatabaseSHACLPath(from: &reader) : nil
        }
    }

    public let conforms: Bool
    public let issues: [Issue]
    public let continuation: DatabaseBytes?

    public init(
        conforms: Bool,
        issues: [Issue],
        continuation: DatabaseBytes? = nil
    ) {
        self.conforms = conforms
        self.issues = issues
        self.continuation = continuation
    }

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeBool(conforms)
        try writer.writeCount(issues.count)
        for issue in issues { try issue.encode(into: &writer) }
        try writer.writeOptionalBytes(continuation)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let conforms = try reader.readBool()
        let count = try reader.readCount()
        var issues: [Issue] = []
        issues.reserveCapacity(count)
        for _ in 0..<count { issues.append(try Issue(from: &reader)) }
        self.init(
            conforms: conforms,
            issues: issues,
            continuation: try reader.readOptionalBytes()
        )
    }
}
