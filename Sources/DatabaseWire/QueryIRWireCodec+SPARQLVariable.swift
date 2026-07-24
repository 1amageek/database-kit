import DatabaseTypes
import DatabaseKit

extension QueryIRWireCodec {
    static func writeSPARQLVariableName(
        _ value: String,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try validateSPARQLVariableName(value)
        try writer.writeString(value)
    }

    static func readSPARQLVariableName(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> String {
        let value = try reader.readString()
        try validateSPARQLVariableName(value)
        return value
    }

    private static func validateSPARQLVariableName(
        _ value: String
    ) throws(DatabaseWireError) {
        do {
            _ = try SPARQLVariableName(value)
        } catch {
            throw .invalidSPARQLVariableName(value)
        }
    }

    static func writeSPARQLIRI(
        _ value: String,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try validateSPARQLIRI(value)
        try writer.writeString(value)
    }

    static func readSPARQLIRI(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> String {
        let value = try reader.readString()
        try validateSPARQLIRI(value)
        return value
    }

    static func writeSPARQLIRIs(
        _ values: [String],
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeCount(values.count)
        for value in values {
            try writeSPARQLIRI(value, into: &writer)
        }
    }

    static func readSPARQLIRIs(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> [String] {
        let count = try reader.readCount()
        var values: [String] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            values.append(try readSPARQLIRI(from: &reader))
        }
        return values
    }

    static func writeOptionalSPARQLIRI(
        _ value: String?,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        guard let value else {
            writer.writeBool(false)
            return
        }
        writer.writeBool(true)
        try writeSPARQLIRI(value, into: &writer)
    }

    static func readOptionalSPARQLIRI(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> String? {
        guard try reader.readBool() else { return nil }
        return try readSPARQLIRI(from: &reader)
    }

    private static func validateSPARQLIRI(
        _ value: String
    ) throws(DatabaseWireError) {
        do {
            _ = try RDFIRI(value)
        } catch {
            throw .invalidRDFIRI(value)
        }
    }
}
