import DatabaseKit
import DatabaseTypes

/// Synchronous closed SQL projection; it cannot escape by copying its destination.
@_spi(DatabaseExecution)
public struct SQLResponseWriter: ~Copyable {
    private var writer: DatabaseWireWriter
    private var remainingResults: Int

    init(writer: DatabaseWireWriter, resultCount: Int) throws(DatabaseWireError) {
        guard resultCount > 0 else { throw .invalidSQLResponse }
        var writer = writer
        try writer.writeCount(resultCount)
        self.writer = writer
        self.remainingResults = resultCount
    }

    public mutating func writeCommand(_ kind: SQLCommandKind, affectedRows: UInt64?)
    throws(DatabaseWireError) {
        try beginResult()
        writer.writeUInt8(2)
        writer.writeUInt8(SQLCommandWireCodec.tag(kind))
        try QueryIRWireFormat.writeOptional(affectedRows, into: &writer) { value, writer in writer.writeUInt64(value) }
        try writer.endNestedValue()
    }

    public mutating func writeCopy(bytes: ByteString, affectedRows: UInt64)
    throws(DatabaseWireError) {
        try beginResult()
        writer.writeUInt8(1)
        try writer.writeBytes(bytes)
        writer.writeUInt64(affectedRows)
        try writer.endNestedValue()
    }

    public mutating func writeRows(
        columnCount: Int, rowCount: Int, affectedRows: UInt64?,
        body: (inout SQLRowWriter) throws -> Void
    ) throws {
        try beginResult()
        writer.writeUInt8(0)
        var rows = try SQLRowWriter(writer: writer, columnCount: columnCount, rowCount: rowCount)
        try body(&rows)
        writer = try rows.finish()
        try QueryIRWireFormat.writeOptional(affectedRows, into: &writer) { value, writer in writer.writeUInt64(value) }
        try writer.endNestedValue()
    }

    private mutating func beginResult() throws(DatabaseWireError) {
        guard remainingResults > 0 else { throw .invalidSQLResponse }
        remainingResults -= 1
        try writer.beginNestedValue()
    }

    mutating func finish() throws(DatabaseWireError) -> DatabaseWireWriter {
        guard remainingResults == 0 else { throw .invalidSQLResponse }
        return writer
    }
}
