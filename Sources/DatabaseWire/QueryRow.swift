import DatabaseTypes

/// One materialized query row.
///
/// Byte-valued fields retain slices of the response frame when the row comes
/// from a `QueryRowIterator`.
public struct QueryRow: Sendable, Hashable {
    public let values: [FieldValue]
    public let annotations: FieldObject
    public let version: ByteString?

    public init(
        values: [FieldValue],
        annotations: FieldObject = FieldObject(),
        version: ByteString? = nil
    ) {
        self.values = values
        self.annotations = annotations
        self.version = version
    }

    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeCount(values.count)
        for value in values {
            try value.encode(into: &writer)
        }
        try annotations.encode(into: &writer)
        try writer.writeOptionalBytes(version)
    }

    init(
        from reader: inout DatabaseWireReader,
        expectedValueCount: Int
    ) throws(DatabaseWireError) {
        let valueCount = try reader.readCount()
        guard valueCount == expectedValueCount else {
            throw .invalidRowValueCount(
                expected: expectedValueCount,
                actual: valueCount
            )
        }
        var values: [FieldValue] = []
        values.reserveCapacity(valueCount)
        for _ in 0..<valueCount {
            values.append(try FieldValue(from: &reader))
        }
        self.init(
            values: values,
            annotations: try FieldObject(from: &reader),
            version: try reader.readOptionalBytes()
        )
    }

    static func validate(
        from reader: inout DatabaseWireReader,
        expectedValueCount: Int
    ) throws(DatabaseWireError) {
        let valueCount = try reader.readCount()
        guard valueCount == expectedValueCount else {
            throw .invalidRowValueCount(
                expected: expectedValueCount,
                actual: valueCount
            )
        }
        for _ in 0..<valueCount {
            try FieldValueWireValidator.validateValue(from: &reader)
        }
        try FieldValueWireValidator.validateObject(from: &reader)
        _ = try reader.readOptionalBytes()
    }
}
