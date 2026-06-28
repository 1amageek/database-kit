/// Convenience top-level codec for DatabaseKit wire DTOs.
public enum DatabaseWireCodec {
    public static let protocolVersion: UInt8 = 1

    public static func encode(schema: DatabaseWireSchema) throws(DatabaseWireError) -> [UInt8] {
        var writer = DatabaseWireBinaryWriter()
        writer.writeUInt8(protocolVersion)
        try schema.encode(into: &writer)
        return writer.bytes
    }

    public static func decodeSchema(_ bytes: [UInt8]) throws(DatabaseWireError) -> DatabaseWireSchema {
        var reader = DatabaseWireBinaryReader(bytes)
        try validateVersion(reader.readUInt8())
        let schema = try DatabaseWireSchema(from: &reader)
        try reader.ensureFullyRead()
        return schema
    }

    public static func encode(record: DatabaseWireRecord) throws(DatabaseWireError) -> [UInt8] {
        var writer = DatabaseWireBinaryWriter()
        writer.writeUInt8(protocolVersion)
        try record.encode(into: &writer)
        return writer.bytes
    }

    public static func decodeRecord(_ bytes: [UInt8]) throws(DatabaseWireError) -> DatabaseWireRecord {
        var reader = DatabaseWireBinaryReader(bytes)
        try validateVersion(reader.readUInt8())
        let record = try DatabaseWireRecord(from: &reader)
        try reader.ensureFullyRead()
        return record
    }

    public static func encode(query: DatabaseWireQueryRequest) throws(DatabaseWireError) -> [UInt8] {
        var writer = DatabaseWireBinaryWriter()
        writer.writeUInt8(protocolVersion)
        try query.encode(into: &writer)
        return writer.bytes
    }

    public static func decodeQuery(_ bytes: [UInt8]) throws(DatabaseWireError) -> DatabaseWireQueryRequest {
        var reader = DatabaseWireBinaryReader(bytes)
        try validateVersion(reader.readUInt8())
        let query = try DatabaseWireQueryRequest(from: &reader)
        try reader.ensureFullyRead()
        return query
    }

    public static func encode(request: DatabaseWireRequest) throws(DatabaseWireError) -> [UInt8] {
        var writer = DatabaseWireBinaryWriter()
        writer.writeUInt8(protocolVersion)
        try request.encode(into: &writer)
        return writer.bytes
    }

    public static func decodeRequest(_ bytes: [UInt8]) throws(DatabaseWireError) -> DatabaseWireRequest {
        var reader = DatabaseWireBinaryReader(bytes)
        try validateVersion(reader.readUInt8())
        let request = try DatabaseWireRequest(from: &reader)
        try reader.ensureFullyRead()
        return request
    }

    public static func encode(response: DatabaseWireResponse) throws(DatabaseWireError) -> [UInt8] {
        var writer = DatabaseWireBinaryWriter()
        writer.writeUInt8(protocolVersion)
        try response.encode(into: &writer)
        return writer.bytes
    }

    public static func decodeResponse(_ bytes: [UInt8]) throws(DatabaseWireError) -> DatabaseWireResponse {
        var reader = DatabaseWireBinaryReader(bytes)
        try validateVersion(reader.readUInt8())
        let response = try DatabaseWireResponse(from: &reader)
        try reader.ensureFullyRead()
        return response
    }

    private static func validateVersion(_ version: UInt8) throws(DatabaseWireError) {
        guard version == protocolVersion else {
            throw DatabaseWireError.unsupportedProtocolVersion(version)
        }
    }
}
