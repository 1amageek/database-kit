import DatabaseValue
import QueryIR

extension QueryIRWireCodec {
    static func encodeLiteral(
        _ literal: Literal,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try QueryIRLiteralWireCodec.encode(literal, into: &writer)
    }

    static func decodeLiteral(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> Literal {
        try QueryIRLiteralWireCodec.decode(from: &reader)
    }

    static func writeRDFDatatypeIRI(
        _ value: String,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        do {
            _ = try DatabaseRDFTypedLiteralDatatype(value)
        } catch {
            throw .invalidRDFDatatypeIRI
        }
        try writer.writeString(value)
    }

    static func readRDFDatatypeIRI(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> String {
        let value = try reader.readString()
        do {
            _ = try DatabaseRDFTypedLiteralDatatype(value)
        } catch {
            throw .invalidRDFDatatypeIRI
        }
        return value
    }

    static func writeRDFLanguageTag(
        _ value: String,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        let language: DatabaseRDFLanguageTag
        do {
            language = try DatabaseRDFLanguageTag(value)
        } catch {
            throw .invalidRDFLanguageTag
        }
        guard language.rawValue == value else {
            throw .nonCanonicalRDFLanguageTag
        }
        try writer.writeString(value)
    }

    static func readRDFLanguageTag(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> String {
        let value = try reader.readString()
        let language: DatabaseRDFLanguageTag
        do {
            language = try DatabaseRDFLanguageTag(value)
        } catch {
            throw .invalidRDFLanguageTag
        }
        guard language.rawValue == value else {
            throw .nonCanonicalRDFLanguageTag
        }
        return value
    }

    static func writeRDFDirection(
        _ value: String,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        guard DatabaseRDFDirection(rawValue: value) != nil else {
            throw .invalidRDFDirectionValue(value)
        }
        try writer.writeString(value)
    }

    static func readRDFDirection(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> String {
        let value = try reader.readString()
        guard DatabaseRDFDirection(rawValue: value) != nil else {
            throw .invalidRDFDirectionValue(value)
        }
        return value
    }
}
