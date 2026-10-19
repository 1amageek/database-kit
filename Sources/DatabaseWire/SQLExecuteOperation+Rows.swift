import DatabaseKit
import DatabaseTypes

extension SQLExecuteOperation {
    /// Complete typed SQL rows retaining their response frame after decode.
    public struct Rows: Sendable {
        private enum Storage: Sendable {
            case materialized([QueryRow])
            case encoded(ByteString)
        }

        public let columns: [QueryColumn]
        public let rowCount: Int
        public let affectedRows: UInt64?
        private let storage: Storage
        private let limits: DatabaseWireLimits

        public init(columns: [QueryColumn], rows: [QueryRow], affectedRows: UInt64? = nil)
        throws(DatabaseWireError) {
            do { try QueryColumn.validate(columns) }
            catch { throw .invalidQueryValue(error) }
            for row in rows { try row.validate(columns: columns) }
            self.columns = columns
            self.rowCount = rows.count
            self.affectedRows = affectedRows
            self.storage = .materialized(rows)
            self.limits = .default
        }

        public func makeRowIterator() -> QueryRowIterator {
            switch storage {
            case .materialized(let rows): return QueryRowIterator(rows: rows)
            case .encoded(let bytes):
                return QueryRowIterator(encodedRows: bytes, rowCount: rowCount,
                    columns: columns, limits: limits)
            }
        }

        func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
            do { try QueryColumn.validate(columns) }
            catch { throw .invalidQueryValue(error) }
            try writer.writeCount(columns.count)
            for column in columns { try column.encode(into: &writer) }
            try writer.writeCount(rowCount)
            switch storage {
            case .materialized(let rows):
                for row in rows {
                    try row.validate(columns: columns)
                    try row.encode(into: &writer)
                }
            case .encoded(let bytes):
                let initialObjects = writer.registeredObjectCount
                var validator = DatabaseWireReader(bytes, limits: writer.limits)
                try validator.beginSubtreeValidation(nestingDepth: writer.currentNestingDepth,
                    registeredObjectCount: initialObjects)
                for _ in 0..<rowCount { try QueryRow.validate(from: &validator, columns: columns) }
                try validator.ensureFullyRead()
                try writer.registerObjects(validator.registeredObjectCount - initialObjects)
                writer.writeUnframedBytes(bytes)
            }
            try QueryIRWireFormat.writeOptional(affectedRows, into: &writer) { value, writer in
                writer.writeUInt64(value)
            }
        }

        init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
            try reader.admitQueryRootRetention()
            let count = try reader.readCount()
            var columns: [QueryColumn] = []
            columns.reserveCapacity(count)
            for _ in 0..<count { columns.append(try QueryColumn(from: &reader)) }
            do { try QueryColumn.validate(columns) }
            catch { throw .invalidQueryValue(error) }
            let rowCount = try reader.readCount()
            let start = reader.consumedByteCount
            for _ in 0..<rowCount { try QueryRow.validate(from: &reader, columns: columns) }
            let bytes = try reader.bytes(inConsumedRange: start..<reader.consumedByteCount)
            let affectedRows: UInt64? = try QueryIRWireFormat.readOptional(from: &reader) {
                (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> UInt64 in try reader.readUInt64()
            }
            self.columns = columns
            self.rowCount = rowCount
            self.affectedRows = affectedRows
            self.storage = .encoded(bytes)
            self.limits = reader.limits
        }
    }
}
