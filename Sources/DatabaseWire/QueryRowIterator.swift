import DatabaseTypes
import DatabaseKit

/// A single-pass iterator that materializes query rows on demand.
public struct QueryRowIterator: Sendable {
    private enum Storage: Sendable {
        case materialized(rows: [QueryRow], nextIndex: Int)
        case encoded(
            reader: DatabaseWireReader,
            remaining: Int,
            columns: [QueryColumn]
        )
    }

    private var storage: Storage

    init(rows: [QueryRow]) {
        storage = .materialized(rows: rows, nextIndex: rows.startIndex)
    }

    init(
        encodedRows: ByteString,
        rowCount: Int,
        columns: [QueryColumn],
        limits: DatabaseWireLimits
    ) {
        storage = .encoded(
            reader: DatabaseWireReader(encodedRows, limits: limits),
            remaining: rowCount,
            columns: columns
        )
    }

    public mutating func next()
        throws(DatabaseWireError) -> QueryRow? {
        switch storage {
        case .materialized(let rows, let nextIndex):
            guard nextIndex < rows.endIndex else {
                return nil
            }
            storage = .materialized(
                rows: rows,
                nextIndex: nextIndex + 1
            )
            return rows[nextIndex]

        case .encoded(var reader, let remaining, let columns):
            guard remaining > 0 else {
                try reader.ensureFullyRead()
                return nil
            }
            let row = try QueryRow(
                from: &reader,
                columns: columns
            )
            let nextRemaining = remaining - 1
            if nextRemaining == 0 {
                try reader.ensureFullyRead()
            }
            storage = .encoded(
                reader: reader,
                remaining: nextRemaining,
                columns: columns
            )
            return row
        }
    }
}
