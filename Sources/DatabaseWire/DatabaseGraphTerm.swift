public import DatabaseValue

/// A vertex or edge label in either a property graph or an RDF graph.
public enum DatabaseGraphTerm: DatabaseWireValue, Hashable {
    case identifier(String)
    case rdf(DatabaseRDFTerm)

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch self {
        case .identifier(let value):
            writer.writeUInt8(1)
            try writer.writeString(value)
        case .rdf(let term):
            writer.writeUInt8(2)
            try term.encode(into: &writer)
        }
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        switch try reader.readUInt8() {
        case 1:
            self = .identifier(try reader.readString())
        case 2:
            self = .rdf(try DatabaseRDFTerm(from: &reader))
        case let tag:
            throw .invalidValueTag(tag)
        }
    }
}
