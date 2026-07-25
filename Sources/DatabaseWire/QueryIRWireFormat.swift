import DatabaseTypes
import DatabaseKit

/// Canonical binary codec for the Foundation-independent query intermediate representation.
public enum QueryIRWireFormat {
    public static func encode(
        _ statement: QueryStatement,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try encodeStatement(statement, into: &writer)
        }
    }

    /// Emits canonical QueryIR bytes into a synchronous borrowed-buffer sink.
    ///
    /// Encoding first performs a measurement pass. `prepare` receives the
    /// exact byte count and completes before any call to `consume`. Each buffer
    /// passed to `consume` is valid only until that call returns and must not be
    /// retained. This API avoids materializing a complete QueryIR payload when
    /// the destination can consume byte spans incrementally.
    public static func emitCanonicalEncoding<DestinationFailure: Error>(
        _ statement: QueryStatement,
        limits: DatabaseWireLimits = .default,
        prepare: (Int) throws(DestinationFailure) -> Void,
        consume: (UnsafeRawBufferPointer) -> Void
    ) throws(DatabaseWireEmissionError<DestinationFailure>) {
        try DatabaseWireWriter.emit(
            limits: limits,
            prepare: prepare,
            consume: consume
        ) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try encodeStatement(statement, into: &writer)
        }
    }

    public static func decode(
        _ bytes: ByteString,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> QueryStatement {
        var reader = DatabaseWireReader(bytes, limits: limits)
        let statement = try decodeStatement(from: &reader)
        try reader.ensureFullyRead()
        return statement
    }

    static func writeOptional<Value>(
        _ value: Value?,
        into writer: inout DatabaseWireWriter,
        encode: (Value, inout DatabaseWireWriter) throws(DatabaseWireError) -> Void
    ) throws(DatabaseWireError) {
        guard let value else {
            writer.writeBool(false)
            return
        }
        writer.writeBool(true)
        try encode(value, &writer)
    }

    static func readOptional<Value>(
        from reader: inout DatabaseWireReader,
        decode: (inout DatabaseWireReader) throws(DatabaseWireError) -> Value
    ) throws(DatabaseWireError) -> Value? {
        guard try reader.readBool() else { return nil }
        return try decode(&reader)
    }

    static func writeArray<Value>(
        _ values: [Value],
        into writer: inout DatabaseWireWriter,
        encode: (Value, inout DatabaseWireWriter) throws(DatabaseWireError) -> Void
    ) throws(DatabaseWireError) {
        try writer.writeCount(values.count)
        for value in values {
            try encode(value, &writer)
        }
    }

    static func readArray<Value>(
        from reader: inout DatabaseWireReader,
        decode: (inout DatabaseWireReader) throws(DatabaseWireError) -> Value
    ) throws(DatabaseWireError) -> [Value] {
        let count = try reader.readCount()
        var values: [Value] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            values.append(try decode(&reader))
        }
        return values
    }

    static func writeOptionalString(
        _ value: String?,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        guard let value else {
            writer.writeBool(false)
            return
        }
        writer.writeBool(true)
        try writer.writeString(value)
    }

    static func readOptionalString(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> String? {
        guard try reader.readBool() else { return nil }
        return try reader.readString()
    }

    static func writeStrings(
        _ values: [String],
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeCount(values.count)
        for value in values {
            try writer.writeString(value)
        }
    }

    static func readStrings(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> [String] {
        let count = try reader.readCount()
        var values: [String] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            values.append(try reader.readString())
        }
        return values
    }

    static func writeOptionalStrings(
        _ values: [String]?,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        guard let values else {
            writer.writeBool(false)
            return
        }
        writer.writeBool(true)
        try writeStrings(values, into: &writer)
    }

    static func readOptionalStrings(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> [String]? {
        guard try reader.readBool() else { return nil }
        return try readStrings(from: &reader)
    }

    static func writeInt(
        _ value: Int,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        guard let exact = Int64(exactly: value) else { throw .byteCountOverflow }
        writer.writeInt64(exact)
    }

    static func readInt(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> Int {
        let value = try reader.readInt64()
        guard let exact = Int(exactly: value) else { throw .byteCountOverflow }
        return exact
    }

    static func writeOptionalInt(
        _ value: Int?,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        guard let value else {
            writer.writeBool(false)
            return
        }
        writer.writeBool(true)
        try writeInt(value, into: &writer)
    }

    static func readOptionalInt(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> Int? {
        guard try reader.readBool() else { return nil }
        return try readInt(from: &reader)
    }

    static func writeOptionalUInt64(
        _ value: UInt64?,
        into writer: inout DatabaseWireWriter
    ) {
        guard let value else {
            writer.writeBool(false)
            return
        }
        writer.writeBool(true)
        writer.writeUInt64(value)
    }

    static func readOptionalUInt64(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> UInt64? {
        guard try reader.readBool() else { return nil }
        return try reader.readUInt64()
    }
}
