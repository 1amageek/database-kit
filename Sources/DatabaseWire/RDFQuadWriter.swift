import DatabaseKit

/// A scoped graph projection with an exact declared quad count.
@_spi(DatabaseExecution)
public struct RDFQuadWriter: ~Copyable {
    private var writer: DatabaseWireWriter
    private var remaining: Int

    init(writer: DatabaseWireWriter, count: Int) throws(DatabaseWireError) {
        var writer = writer
        try writer.writeCount(count)
        self.writer = writer
        remaining = count
    }

    public mutating func write(_ quad: RDFQuad) throws(DatabaseWireError) {
        guard remaining > 0 else { throw .invalidSQLResponse }
        try quad.encode(into: &writer)
        remaining -= 1
    }

    mutating func finish() throws(DatabaseWireError) -> DatabaseWireWriter {
        guard remaining == 0 else { throw .invalidSQLResponse }
        return writer
    }
}
