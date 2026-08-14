import DatabaseTypes
import DatabaseKit

/// An owner-retaining page of query rows.
///
/// Decoding validates every row in place and stores one range of the response
/// frame. Rows are constructed only when requested from an iterator.
public struct QueryRowPage: Sendable {
    private enum Storage: Sendable {
        case materialized([QueryRow])
        case encoded(ByteString)
    }

    public let columns: [QueryColumn]
    public let rowCount: Int
    public let continuation: ByteString?
    #if DATABASE_KIT_MULTIPLE_BASES
    public let provenance: CompositionPageProvenance?
    public let consistency: DatabaseReadConsistency
    #else
    public let snapshotVersion: UInt64?
    #endif

    private let storage: Storage
    private let limits: DatabaseWireLimits

    var retainedEncodedRows: ByteString? {
        guard case .encoded(let bytes) = storage else {
            return nil
        }
        return bytes
    }

    #if DATABASE_KIT_MULTIPLE_BASES
    public init(
        columns: [QueryColumn],
        rows: [QueryRow],
        continuation: ByteString? = nil,
        provenance: CompositionPageProvenance?,
        consistency: DatabaseReadConsistency
    ) throws(DatabaseWireError) {
        for row in rows {
            guard row.values.count == columns.count else {
                throw .invalidRowValueCount(
                    expected: columns.count,
                    actual: row.values.count
                )
            }
        }
        guard provenance == nil || provenance?.originCount == rows.count else {
            throw .invalidCompositionProvenance
        }
        self.columns = columns
        self.rowCount = rows.count
        self.continuation = continuation
        self.provenance = provenance
        self.consistency = consistency
        self.storage = .materialized(rows)
        self.limits = .default
    }
    #else
    public init(
        columns: [QueryColumn],
        rows: [QueryRow],
        continuation: ByteString? = nil,
        snapshotVersion: UInt64? = nil
    ) throws(DatabaseWireError) {
        for row in rows {
            guard row.values.count == columns.count else {
                throw .invalidRowValueCount(
                    expected: columns.count,
                    actual: row.values.count
                )
            }
        }
        self.columns = columns
        self.rowCount = rows.count
        self.continuation = continuation
        self.snapshotVersion = snapshotVersion
        self.storage = .materialized(rows)
        self.limits = .default
    }
    #endif

    public func makeRowIterator() -> QueryRowIterator {
        switch storage {
        case .materialized(let rows):
            return QueryRowIterator(rows: rows)
        case .encoded(let bytes):
            return QueryRowIterator(
                encodedRows: bytes,
                rowCount: rowCount,
                columnCount: columns.count,
                limits: limits
            )
        }
    }

    public func materializedRows(
        maximumCount: Int
    ) throws(DatabaseWireError) -> [QueryRow] {
        guard maximumCount >= 0 else {
            throw .byteCountOverflow
        }
        guard rowCount <= maximumCount else {
            throw .collectionTooLarge(
                actual: rowCount,
                maximum: maximumCount
            )
        }
        var rows: [QueryRow] = []
        rows.reserveCapacity(rowCount)
        var iterator = makeRowIterator()
        while let row = try iterator.next() {
            rows.append(row)
        }
        return rows
    }

    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeCount(columns.count)
        for column in columns {
            try column.encode(into: &writer)
        }
        try writer.writeCount(rowCount)
        switch storage {
        case .materialized(let rows):
            for row in rows {
                try row.encode(into: &writer)
            }
        case .encoded(let bytes):
            let initialObjectCount = writer.registeredObjectCount
            var validator = DatabaseWireReader(
                bytes,
                limits: writer.limits
            )
            try validator.beginSubtreeValidation(
                nestingDepth: writer.currentNestingDepth,
                registeredObjectCount: initialObjectCount
            )
            for _ in 0..<rowCount {
                try QueryRow.validate(
                    from: &validator,
                    expectedValueCount: columns.count
                )
            }
            try validator.ensureFullyRead()
            try writer.registerObjects(
                validator.registeredObjectCount - initialObjectCount
            )
            writer.writeUnframedBytes(bytes)
        }
        #if DATABASE_KIT_MULTIPLE_BASES
        writer.writeBool(provenance != nil)
        if let provenance {
            guard provenance.originCount == rowCount else {
                throw .invalidCompositionProvenance
            }
            try provenance.encode(into: &writer)
        }
        try consistency.encode(into: &writer)
        try writer.writeOptionalBytes(continuation)
        #else
        try writer.writeOptionalBytes(continuation)
        writer.writeBool(snapshotVersion != nil)
        if let snapshotVersion {
            writer.writeUInt64(snapshotVersion)
        }
        #endif
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let columnCount = try reader.readCount()
        var columns: [QueryColumn] = []
        columns.reserveCapacity(columnCount)
        for _ in 0..<columnCount {
            columns.append(try QueryColumn(from: &reader))
        }

        let rowCount = try reader.readCount()
        let rowsStart = reader.consumedByteCount
        for _ in 0..<rowCount {
            try QueryRow.validate(
                from: &reader,
                expectedValueCount: columnCount
            )
        }
        let rowsEnd = reader.consumedByteCount
        let encodedRows = try reader.bytes(
            inConsumedRange: rowsStart..<rowsEnd
        )

        self.columns = columns
        self.rowCount = rowCount
        #if DATABASE_KIT_MULTIPLE_BASES
        self.provenance = try reader.readBool()
            ? try CompositionPageProvenance(from: &reader)
            : nil
        guard provenance == nil || provenance?.originCount == rowCount else {
            throw .invalidCompositionProvenance
        }
        self.consistency = try DatabaseReadConsistency(from: &reader)
        self.continuation = try reader.readOptionalBytes()
        #else
        self.continuation = try reader.readOptionalBytes()
        self.snapshotVersion =
            try reader.readBool() ? try reader.readUInt64() : nil
        #endif
        self.storage = .encoded(encodedRows)
        self.limits = reader.limits
    }
}
