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
    public let affectedRows: UInt64?
    public let metadata: FieldObject
    public let continuation: ByteString?
    #if DATABASE_KIT_MULTI_BASE
    public let provenance: CompositionPageProvenance?
    public let consistency: DatabaseReadConsistency?
    #else
    public let snapshotVersion: UInt64?
    #endif

    private let storage: Storage
    private let limits: DatabaseWireLimits

    /// The known-valid zero-column, zero-row value for non-row outcomes.
    public static var empty: Self { Self() }

    private init() {
        columns = []
        rowCount = 0
        affectedRows = nil
        metadata = FieldObject()
        continuation = nil
        #if DATABASE_KIT_MULTI_BASE
        provenance = nil
        consistency = nil
        #else
        snapshotVersion = nil
        #endif
        storage = .materialized([])
        limits = .default
    }

    var retainedEncodedRows: ByteString? {
        guard case .encoded(let bytes) = storage else {
            return nil
        }
        return bytes
    }

    #if DATABASE_KIT_MULTI_BASE
    public init(
        columns: [QueryColumn],
        rows: [QueryRow],
        continuation: ByteString? = nil,
        provenance: CompositionPageProvenance? = nil,
        consistency: DatabaseReadConsistency? = nil,
        affectedRows: UInt64? = nil,
        metadata: FieldObject = FieldObject()
    ) throws(DatabaseWireError) {
        do { try QueryColumn.validate(columns) }
        catch let error { throw .invalidQueryValue(error) }
        for row in rows { try row.validate(columns: columns) }
        guard provenance == nil || provenance?.originCount == rows.count else {
            throw .invalidCompositionProvenance
        }
        self.columns = columns
        self.rowCount = rows.count
        self.affectedRows = affectedRows
        self.metadata = metadata
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
        snapshotVersion: UInt64? = nil,
        affectedRows: UInt64? = nil,
        metadata: FieldObject = FieldObject()
    ) throws(DatabaseWireError) {
        do { try QueryColumn.validate(columns) }
        catch let error { throw .invalidQueryValue(error) }
        for row in rows { try row.validate(columns: columns) }
        self.columns = columns
        self.rowCount = rows.count
        self.affectedRows = affectedRows
        self.metadata = metadata
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
                columns: columns,
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
        do { try QueryColumn.validate(columns) }
        catch let error { throw .invalidQueryValue(error) }
        try writer.writeCount(columns.count)
        for column in columns {
            try column.encode(into: &writer)
        }
        try writer.writeCount(rowCount)
        switch storage {
        case .materialized(let rows):
            for row in rows {
                try row.validate(columns: columns)
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
                    columns: columns
                )
            }
            try validator.ensureFullyRead()
            try writer.registerObjects(
                validator.registeredObjectCount - initialObjectCount
            )
            writer.writeUnframedBytes(bytes)
        }
        #if DATABASE_KIT_MULTI_BASE
        try Self.encodeFooter(provenance: provenance, consistency: consistency,
            continuation: continuation, affectedRows: affectedRows, metadata: metadata, into: &writer)
        #else
        try Self.encodeFooter(snapshotVersion: snapshotVersion,
            continuation: continuation, affectedRows: affectedRows, metadata: metadata, into: &writer)
        #endif
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        try reader.admitQueryRootRetention()
        let columnCount = try reader.readCount()
        var columns: [QueryColumn] = []
        columns.reserveCapacity(columnCount)
        for _ in 0..<columnCount {
            columns.append(try QueryColumn(from: &reader))
        }

        do { try QueryColumn.validate(columns) }
        catch let error { throw .invalidQueryValue(error) }
        let rowCount = try reader.readCount()
        let rowsStart = reader.consumedByteCount
        for _ in 0..<rowCount {
            try QueryRow.validate(
                from: &reader,
                columns: columns
            )
        }
        let rowsEnd = reader.consumedByteCount
        let encodedRows = try reader.bytes(
            inConsumedRange: rowsStart..<rowsEnd
        )

        self.columns = columns
        self.rowCount = rowCount
        #if DATABASE_KIT_MULTI_BASE
        self.provenance = try reader.readBool()
            ? try CompositionPageProvenance(from: &reader)
            : nil
        guard provenance == nil || provenance?.originCount == rowCount else {
            throw .invalidCompositionProvenance
        }
        self.consistency = try reader.readBool() ? DatabaseReadConsistency(from: &reader) : nil
        self.continuation = try reader.readOptionalBytes()
        #else
        self.continuation = try reader.readOptionalBytes()
        self.snapshotVersion =
            try reader.readBool() ? try reader.readUInt64() : nil
        #endif
        self.affectedRows = try QueryIRWireFormat.readOptional(from: &reader) {
            (reader: inout DatabaseWireReader) throws(DatabaseWireError) in try reader.readUInt64()
        }
        self.metadata = try FieldObject(from: &reader)
        self.storage = .encoded(encodedRows)
        self.limits = reader.limits
    }
    #if DATABASE_KIT_MULTI_BASE
    static func encodeFooter(provenance: CompositionPageProvenance?,
        consistency: DatabaseReadConsistency?, continuation: ByteString?,
        affectedRows: UInt64?, metadata: FieldObject, into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeBool(provenance != nil)
        if let provenance { try provenance.encode(into: &writer) }
        writer.writeBool(consistency != nil)
        if let consistency { try consistency.encode(into: &writer) }
        try writer.writeOptionalBytes(continuation)
        try encodeOutcomeMetadata(affectedRows: affectedRows, metadata: metadata, into: &writer)
    }
    #else
    static func encodeFooter(snapshotVersion: UInt64?, continuation: ByteString?,
        affectedRows: UInt64?, metadata: FieldObject, into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeOptionalBytes(continuation)
        writer.writeBool(snapshotVersion != nil)
        if let snapshotVersion { writer.writeUInt64(snapshotVersion) }
        try encodeOutcomeMetadata(affectedRows: affectedRows, metadata: metadata, into: &writer)
    }
    #endif

    private static func encodeOutcomeMetadata(affectedRows: UInt64?, metadata: FieldObject,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try QueryIRWireFormat.writeOptional(affectedRows, into: &writer) { count, writer in
            writer.writeUInt64(count)
        }
        try metadata.encode(into: &writer)
    }

}
