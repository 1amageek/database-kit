import DatabaseTypes
import DatabaseKit

extension DatabaseKit.QueryRow {
    func validate(columns: [QueryColumn]) throws(DatabaseWireError) {
        guard values.count == columns.count else {
            throw .invalidRowValueCount(expected: columns.count, actual: values.count)
        }
        for (value, column) in zip(values, columns) {
            try Self.validate(value, column: column)
        }
    }

    static func validate(_ value: QueryValue, column: QueryColumn) throws(DatabaseWireError) {
        guard (column.isNullable || !value.isNull),
              QueryValueValidator.accepts(value, type: column.type) else {
            throw .invalidQueryValue(.incompatibleType)
        }
    }

    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeCount(values.count)
        for value in values {
            try QueryValueWireCodec.encode(value, into: &writer)
        }
        try annotations.encode(into: &writer)
        try writer.writeOptionalBytes(version)
    }

    init(
        from reader: inout DatabaseWireReader,
        columns: [QueryColumn]
    ) throws(DatabaseWireError) {
        let valueCount = try reader.readCount()
        guard valueCount == columns.count else {
            throw .invalidRowValueCount(
                expected: columns.count,
                actual: valueCount
            )
        }
        var values: [QueryValue] = []
        values.reserveCapacity(valueCount)
        for column in columns {
            let value = try QueryValueWireCodec.decode(from: &reader)
            try Self.validate(value, column: column)
            values.append(value)
        }
        self.init(
            values: values,
            annotations: try FieldObject(from: &reader),
            version: try reader.readOptionalBytes()
        )
    }

    static func validate(
        from reader: inout DatabaseWireReader,
        columns: [QueryColumn]
    ) throws(DatabaseWireError) {
        let valueCount = try reader.readCount()
        guard valueCount == columns.count else {
            throw .invalidRowValueCount(
                expected: columns.count,
                actual: valueCount
            )
        }
        for column in columns {
            try QueryValueWireCodec.validate(from: &reader, type: column.type,
                                             isNullable: column.isNullable)
        }
        try FieldValueWireValidator.validateObject(from: &reader)
        _ = try reader.readOptionalBytes()
    }
}
