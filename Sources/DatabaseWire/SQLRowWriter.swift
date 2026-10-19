import DatabaseKit
import DatabaseTypes

/// One scoped SQL rows outcome, validating columns and cells before completion.
@_spi(DatabaseExecution)
public struct SQLRowWriter: ~Copyable {
    private var writer: DatabaseWireWriter
    private let columnCount: Int
    private let rowCount: Int
    private var columns: [QueryColumn]
    private var rowCountWritten = false
    private var completedRows = 0
    private var activeCellCount: Int?

    init(writer: DatabaseWireWriter, columnCount: Int, rowCount: Int)
    throws(DatabaseWireError) {
        var writer = writer
        try writer.writeCount(columnCount)
        guard rowCount >= 0, rowCount <= writer.limits.maximumCollectionCount else {
            throw .collectionTooLarge(actual: rowCount, maximum: writer.limits.maximumCollectionCount)
        }
        self.writer = writer
        self.columnCount = columnCount
        self.rowCount = rowCount
        self.columns = []
        columns.reserveCapacity(columnCount)
    }

    public mutating func writeColumn(_ column: QueryColumn) throws(DatabaseWireError) {
        guard !rowCountWritten, columns.count < columnCount,
              UInt64(column.number) == UInt64(columns.count) + 1 else { throw .invalidSQLResponse }
        try column.encode(into: &writer)
        columns.append(column)
    }

    public mutating func beginRow() throws(DatabaseWireError) {
        guard activeCellCount == nil, completedRows < rowCount else { throw .invalidSQLResponse }
        try writeRowCountIfNeeded()
        try writer.writeCount(columnCount)
        activeCellCount = 0
    }

    public mutating func writeValue(_ value: QueryValue) throws(DatabaseWireError) {
        guard let count = activeCellCount, count < columnCount else { throw .invalidSQLResponse }
        try QueryRow.validate(value, column: columns[count])
        try QueryValueWireCodec.encode(value, into: &writer)
        activeCellCount = count + 1
    }

    public mutating func endRow(
        annotations: FieldObject = FieldObject(), version: ByteString? = nil
    ) throws(DatabaseWireError) {
        guard activeCellCount == columnCount else { throw .invalidSQLResponse }
        try annotations.encode(into: &writer)
        try writer.writeOptionalBytes(version)
        activeCellCount = nil
        completedRows += 1
    }

    private mutating func writeRowCountIfNeeded() throws(DatabaseWireError) {
        guard columns.count == columnCount else { throw .invalidSQLResponse }
        if !rowCountWritten {
            try writer.writeCount(rowCount)
            rowCountWritten = true
        }
    }

    mutating func finish() throws(DatabaseWireError) -> DatabaseWireWriter {
        guard activeCellCount == nil, completedRows == rowCount else { throw .invalidSQLResponse }
        try writeRowCountIfNeeded()
        return writer
    }
}
