import DatabaseTypes
import DatabaseValue

public struct DatabaseRDFQuad: DatabaseWireValue, Hashable {
    public let subject: RDFTerm
    public let predicate: RDFTerm
    public let object: RDFTerm
    public let graph: RDFTerm?

    public init(
        subject: RDFTerm,
        predicate: RDFTerm,
        object: RDFTerm,
        graph: RDFTerm? = nil
    ) throws(DatabaseWireError) {
        do {
            try RDFTermCodec.validate(subject, role: .subject)
            try RDFTermCodec.validate(predicate, role: .predicate)
            try RDFTermCodec.validate(object, role: .object)
            if let graph {
                try RDFTermCodec.validate(graph, role: .graphName)
            }
        } catch let error {
            throw .invalidCanonicalRDFTerm(error)
        }
        self.subject = subject
        self.predicate = predicate
        self.object = object
        self.graph = graph
    }

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeCanonicalRDFTerm(subject, role: .subject)
        try writer.writeCanonicalRDFTerm(predicate, role: .predicate)
        try writer.writeCanonicalRDFTerm(object, role: .object)
        writer.writeBool(graph != nil)
        if let graph {
            try writer.writeCanonicalRDFTerm(graph, role: .graphName)
        }
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.subject = try reader.readCanonicalRDFTerm(role: .subject)
        self.predicate = try reader.readCanonicalRDFTerm(role: .predicate)
        self.object = try reader.readCanonicalRDFTerm(role: .object)
        self.graph = try reader.readBool()
            ? try reader.readCanonicalRDFTerm(role: .graphName)
            : nil
    }
}
