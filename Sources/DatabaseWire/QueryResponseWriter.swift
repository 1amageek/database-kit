import DatabaseKit
import DatabaseTypes

/// Synchronous closed query projection; its destination cannot escape by copying.
@_spi(DatabaseExecution)
public struct QueryResponseWriter: ~Copyable {
    private var writer: DatabaseWireWriter
    private var remainingResults: Int
    private let isBlock: Bool

    init(writer: DatabaseWireWriter, resultCount: Int) throws(DatabaseWireError) {
        guard resultCount > 0 else { throw .invalidSQLResponse }
        var writer = writer
        let isBlock = resultCount != 1
        if isBlock { writer.writeUInt8(6); try writer.writeCount(resultCount) }
        self.isBlock = isBlock
        self.writer = writer
        self.remainingResults = resultCount
    }

    public mutating func writeCommand(_ kind: SQLCommandKind, affectedRows: UInt64?)
    throws(DatabaseWireError) {
        try beginResult()
        writer.writeUInt8(4)
        writer.writeUInt8(SQLCommandWireCodec.tag(kind))
        try QueryIRWireFormat.writeOptional(affectedRows, into: &writer) { value, writer in writer.writeUInt64(value) }
        if isBlock { try writer.endNestedValue() }
    }

    public mutating func writeCopy(bytes: ByteString, affectedRows: UInt64)
    throws(DatabaseWireError) {
        try beginResult()
        writer.writeUInt8(5)
        try writer.writeBytes(bytes)
        writer.writeUInt64(affectedRows)
        if isBlock { try writer.endNestedValue() }
    }

    #if DATABASE_KIT_MULTI_BASE
    public mutating func writeBoolean(_ value: QueryBooleanResult) throws(DatabaseWireError) {
        try beginResult()
        writer.writeUInt8(2)
        try value.encode(into: &writer)
        if isBlock { try writer.endNestedValue() }
    }

    public mutating func writeRDFGraph(quadCount: Int,
        provenance: CompositionPageProvenance? = nil, consistency: DatabaseReadConsistency,
        body: (inout RDFQuadWriter) throws -> Void) throws {
        try beginResult()
        writer.writeUInt8(3)
        var quads = try RDFQuadWriter(writer: writer, count: quadCount)
        try body(&quads)
        writer = try quads.finish()
        try RDFGraphPage.encodeFooter(quadCount: quadCount, provenance: provenance,
            consistency: consistency, continuation: nil, into: &writer)
        if isBlock { try writer.endNestedValue() }
    }
    #else
    public mutating func writeBoolean(_ value: Bool) throws(DatabaseWireError) {
        try beginResult()
        writer.writeUInt8(2)
        writer.writeBool(value)
        if isBlock { try writer.endNestedValue() }
    }

    public mutating func writeRDFGraph(quadCount: Int, snapshotVersion: Int64? = nil,
        body: (inout RDFQuadWriter) throws -> Void) throws {
        try beginResult()
        writer.writeUInt8(3)
        var quads = try RDFQuadWriter(writer: writer, count: quadCount)
        try body(&quads)
        writer = try quads.finish()
        try RDFGraphPage.encodeFooter(snapshotVersion: snapshotVersion, continuation: nil, into: &writer)
        if isBlock { try writer.endNestedValue() }
    }
    #endif

    public mutating func writeRows(
        columnCount: Int, rowCount: Int, affectedRows: UInt64?,
        metadata: FieldObject = FieldObject(),
        body: (inout SQLRowWriter) throws -> Void
    ) throws {
        try beginResult()
        writer.writeUInt8(1)
        var rows = try SQLRowWriter(writer: writer, columnCount: columnCount, rowCount: rowCount)
        try body(&rows)
        writer = try rows.finish()
        #if DATABASE_KIT_MULTI_BASE
        try QueryRowPage.encodeFooter(provenance: nil, consistency: nil,
            continuation: nil, affectedRows: affectedRows, metadata: metadata, into: &writer)
        #else
        try QueryRowPage.encodeFooter(snapshotVersion: nil,
            continuation: nil, affectedRows: affectedRows, metadata: metadata, into: &writer)
        #endif
        if isBlock { try writer.endNestedValue() }
    }

    private mutating func beginResult() throws(DatabaseWireError) {
        guard remainingResults > 0 else { throw .invalidSQLResponse }
        remainingResults -= 1
        if isBlock { try writer.beginNestedValue() }
    }

    mutating func finish() throws(DatabaseWireError) -> DatabaseWireWriter {
        guard remainingResults == 0 else { throw .invalidSQLResponse }
        return writer
    }
}
