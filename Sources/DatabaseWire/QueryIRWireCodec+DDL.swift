import DatabaseKit

extension QueryIRWireFormat {
    static func encodeDDL(_ value: SQLDDLStatement, into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try writer.withNestedValue { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            switch value {
            case .createSchema(let name, let flag):
                writer.writeUInt8(0)
                try writer.writeString(name)
                writer.writeBool(flag)
            case .renameSchema(let name, let target):
                writer.writeUInt8(1)
                try writer.writeString(name)
                try writer.writeString(target)
            case .dropSchema(let names, let flag, let behavior):
                writer.writeUInt8(2)
                try writeStrings(names, into: &writer)
                writer.writeBool(flag)
                encodeDropBehavior(behavior, into: &writer)
            case .createTable(let value):
                writer.writeUInt8(3)
                try encodeDDLCreateTable(value, into: &writer)
            case .alterTable(let value):
                writer.writeUInt8(4)
                try encodeTableRef(value.name, into: &writer)
                try writeArray(value.actions, into: &writer, encode: encodeDDLAlterAction)
                writer.writeBool(value.ifExists)
            case .dropTable(let names, let flag, let behavior):
                writer.writeUInt8(5)
                try writeArray(names, into: &writer, encode: encodeTableRef)
                writer.writeBool(flag)
                encodeDropBehavior(behavior, into: &writer)
            case .createIndex(let value):
                writer.writeUInt8(6)
                try encodeTableRef(value.name, into: &writer)
                try encodeTableRef(value.table, into: &writer)
                try writeArray(value.keys, into: &writer, encode: encodeSortKey)
                try writeOptional(value.predicate, into: &writer, encode: encodeExpression)
                writer.writeBool(value.unique)
                encodeDDLNulls(value.nulls, into: &writer)
                writer.writeBool(value.ifNotExists)
            case .dropIndex(let names, let flag, let behavior):
                writer.writeUInt8(7)
                try writeArray(names, into: &writer, encode: encodeTableRef)
                writer.writeBool(flag)
                encodeDropBehavior(behavior, into: &writer)
            case .createView(let value):
                writer.writeUInt8(8)
                try encodeTableRef(value.name, into: &writer)
                try writeOptionalStrings(value.columns, into: &writer)
                try encodeSelectQuery(value.query, into: &writer)
                writer.writeBool(value.orReplace)
            case .dropView(let names, let flag, let behavior):
                writer.writeUInt8(9)
                try writeArray(names, into: &writer, encode: encodeTableRef)
                writer.writeBool(flag)
                encodeDropBehavior(behavior, into: &writer)
            case .createMaterializedView(let value):
                writer.writeUInt8(10)
                try encodeTableRef(value.name, into: &writer)
                try writeOptionalStrings(value.columns, into: &writer)
                try encodeSelectQuery(value.query, into: &writer)
                writer.writeBool(value.withData)
                writer.writeBool(value.ifNotExists)
            case .refreshMaterializedView(let name, let withData):
                writer.writeUInt8(11)
                try encodeTableRef(name, into: &writer)
                writer.writeBool(withData)
            case .dropMaterializedView(let names, let flag, let behavior):
                writer.writeUInt8(12)
                try writeArray(names, into: &writer, encode: encodeTableRef)
                writer.writeBool(flag)
                encodeDropBehavior(behavior, into: &writer)
            case .createSequence(let value):
                writer.writeUInt8(13)
                try encodeTableRef(value.name, into: &writer)
                try encodeDDLSequenceOptions(value.options, into: &writer)
                try writeOptional(value.ownedBy, into: &writer, encode: encodeDDLOwnership)
                writer.writeBool(value.ifNotExists)
            case .alterSequence(let value):
                writer.writeUInt8(14)
                try encodeTableRef(value.name, into: &writer)
                try encodeDDLSequenceOptions(value.options, into: &writer)
                try writeOptional(value.restart, into: &writer, encode: encodeDDLRestart)
                try writeOptional(value.ownedBy, into: &writer, encode: encodeDDLOwnership)
                try writeOptionalString(value.renameTo, into: &writer)
                writer.writeBool(value.ifExists)
            case .dropSequence(let names, let flag, let behavior):
                writer.writeUInt8(15)
                try writeArray(names, into: &writer, encode: encodeTableRef)
                writer.writeBool(flag)
                encodeDropBehavior(behavior, into: &writer)
            }
        }
    }

    static func decodeDDL(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLDDLStatement {
        try reader.beginQueryPayload()
        defer { reader.endQueryPayload() }
        return try reader.withNestedValue { (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLDDLStatement in
            switch try reader.readUInt8() {
            case 0: return .createSchema(name: try reader.readString(), ifNotExists: try reader.readBool())
            case 1: return .renameSchema(name: try reader.readString(), to: try reader.readString())
            case 2: return .dropSchema(names: try readDDLStrings(from: &reader), ifExists: try reader.readBool(), behavior: try decodeDropBehavior(from: &reader))
            case 3: return .createTable(try decodeDDLCreateTable(from: &reader))
            case 4: return .alterTable(SQLAlterTable(name: try decodeTableRef(from: &reader), actions: try readDDLArray(from: &reader, decode: decodeDDLAlterAction), ifExists: try reader.readBool()))
            case 5: return .dropTable(names: try readDDLArray(from: &reader, decode: decodeTableRef), ifExists: try reader.readBool(), behavior: try decodeDropBehavior(from: &reader))
            case 6: return .createIndex(SQLCreateIndex(name: try decodeTableRef(from: &reader), table: try decodeTableRef(from: &reader), keys: try readDDLArray(from: &reader, decode: decodeSortKey), predicate: try readOptional(from: &reader, decode: decodeExpression), unique: try reader.readBool(), nulls: try decodeDDLNulls(from: &reader), ifNotExists: try reader.readBool()))
            case 7: return .dropIndex(names: try readDDLArray(from: &reader, decode: decodeTableRef), ifExists: try reader.readBool(), behavior: try decodeDropBehavior(from: &reader))
            case 8: return .createView(SQLCreateView(name: try decodeTableRef(from: &reader), columns: try readDDLOptionalStrings(from: &reader), query: try decodeSelectQuery(from: &reader), orReplace: try reader.readBool()))
            case 9: return .dropView(names: try readDDLArray(from: &reader, decode: decodeTableRef), ifExists: try reader.readBool(), behavior: try decodeDropBehavior(from: &reader))
            case 10: return .createMaterializedView(SQLCreateMaterializedView(name: try decodeTableRef(from: &reader), columns: try readDDLOptionalStrings(from: &reader), query: try decodeSelectQuery(from: &reader), withData: try reader.readBool(), ifNotExists: try reader.readBool()))
            case 11: return .refreshMaterializedView(name: try decodeTableRef(from: &reader), withData: try reader.readBool())
            case 12: return .dropMaterializedView(names: try readDDLArray(from: &reader, decode: decodeTableRef), ifExists: try reader.readBool(), behavior: try decodeDropBehavior(from: &reader))
            case 13: return .createSequence(SQLCreateSequence(name: try decodeTableRef(from: &reader), options: try decodeDDLSequenceOptions(from: &reader), ownedBy: try readOptional(from: &reader, decode: decodeDDLOwnership), ifNotExists: try reader.readBool()))
            case 14: return .alterSequence(SQLAlterSequence(name: try decodeTableRef(from: &reader), options: try decodeDDLSequenceOptions(from: &reader), restart: try readOptional(from: &reader, decode: decodeDDLRestart), ownedBy: try readOptional(from: &reader, decode: decodeDDLOwnership), renameTo: try readOptionalString(from: &reader), ifExists: try reader.readBool()))
            case 15: return .dropSequence(names: try readDDLArray(from: &reader, decode: decodeTableRef), ifExists: try reader.readBool(), behavior: try decodeDropBehavior(from: &reader))
            case let tag: throw .invalidValueTag(tag)
            }
        }
    }

    private static func encodeDDLCreateTable(_ value: SQLCreateTable, into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try encodeTableRef(value.name, into: &writer)
        switch value.source {
        case .columns(let columns, let constraints):
            writer.writeUInt8(0)
            try writeArray(columns, into: &writer, encode: encodeDDLColumn)
            try writeArray(constraints, into: &writer, encode: encodeDDLConstraint)
        case .query(let query, let columns, let withData):
            writer.writeUInt8(1)
            try encodeSelectQuery(query, into: &writer)
            try writeOptionalStrings(columns, into: &writer)
            writer.writeBool(withData)
        }
        writer.writeBool(value.temporary)
        writer.writeBool(value.ifNotExists)
    }

    private static func decodeDDLCreateTable(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLCreateTable {
        let name = try decodeTableRef(from: &reader)
        let source: SQLTableDefinition
        switch try reader.readUInt8() {
        case 0: source = .columns(try readDDLArray(from: &reader, decode: decodeDDLColumn), constraints: try readDDLArray(from: &reader, decode: decodeDDLConstraint))
        case 1: source = .query(try decodeSelectQuery(from: &reader), columns: try readDDLOptionalStrings(from: &reader), withData: try reader.readBool())
        case let tag: throw .invalidValueTag(tag)
        }
        return SQLCreateTable(name: name, source: source, temporary: try reader.readBool(), ifNotExists: try reader.readBool())
    }

    private static func encodeDDLColumn(_ value: SQLColumnDefinition, into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try writer.withNestedValue { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writer.writeString(value.name)
            try encodeDataType(value.type, into: &writer)
            switch value.policy {
            case .input(let expression):
                writer.writeUInt8(0)
                try writeOptional(expression, into: &writer, encode: encodeExpression)
            case .generated(let expression, let stored):
                writer.writeUInt8(1)
                try encodeExpression(expression, into: &writer)
                writer.writeBool(stored)
            case .identity(let generation, let options):
                writer.writeUInt8(2)
                writer.writeUInt8(generation == .always ? 0 : 1)
                try encodeDDLSequenceOptions(options, into: &writer)
            case .serial: writer.writeUInt8(3)
            }
            try writeArray(value.constraints, into: &writer, encode: encodeDDLConstraint)
        }
    }

    private static func decodeDDLColumn(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLColumnDefinition {
        try reader.withNestedValue { (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLColumnDefinition in
            let name = try reader.readString()
            let type = try decodeDataType(from: &reader)
            let policy: SQLColumnDefinitionPolicy
            switch try reader.readUInt8() {
            case 0: policy = .input(defaultExpression: try readOptional(from: &reader, decode: decodeExpression))
            case 1: policy = .generated(try decodeExpression(from: &reader), stored: try reader.readBool())
            case 2:
                let generation: SQLIdentityGeneration
                switch try reader.readUInt8() {
                case 0: generation = .always
                case 1: generation = .byDefault
                case let tag: throw .invalidValueTag(tag)
                }
                policy = .identity(generation: generation, options: try decodeDDLSequenceOptions(from: &reader))
            case 3: policy = .serial
            case let tag: throw .invalidValueTag(tag)
            }
            return SQLColumnDefinition(name: name, type: type, policy: policy, constraints: try readDDLArray(from: &reader, decode: decodeDDLConstraint))
        }
    }

    private static func encodeDDLConstraint(_ value: SQLTableConstraint, into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try writer.withNestedValue { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writeOptionalString(value.name, into: &writer)
            switch value.timing {
            case .immediate: writer.writeUInt8(0)
            case .deferrable(let deferred): writer.writeUInt8(1); writer.writeBool(deferred)
            }
            switch value.kind {
            case .primaryKey(let columns):
                writer.writeUInt8(0)
                try writeStrings(columns, into: &writer)
            case .unique(let columns, let nulls):
                writer.writeUInt8(1)
                try writeStrings(columns, into: &writer)
                encodeDDLNulls(nulls, into: &writer)
            case .notNull(let column):
                writer.writeUInt8(2)
                try writer.writeString(column)
            case .check(let expression):
                writer.writeUInt8(3)
                try encodeExpression(expression, into: &writer)
            case .foreignKey(let foreign):
                writer.writeUInt8(4)
                try writeStrings(foreign.columns, into: &writer)
                try encodeTableRef(foreign.referencedTable, into: &writer)
                try writeOptionalStrings(foreign.referencedColumns, into: &writer)
                writer.writeUInt8(foreign.match == .simple ? 0 : 1)
                encodeDDLReferentialAction(foreign.onUpdate, into: &writer)
                encodeDDLReferentialAction(foreign.onDelete, into: &writer)
                try writeOptionalStrings(foreign.onDeleteColumns, into: &writer)
            }
        }
    }

    private static func decodeDDLConstraint(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLTableConstraint {
        try reader.withNestedValue { (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLTableConstraint in
            let name = try readOptionalString(from: &reader)
            let timing: SQLConstraintTiming
            switch try reader.readUInt8() {
            case 0: timing = .immediate
            case 1: timing = .deferrable(initiallyDeferred: try reader.readBool())
            case let tag: throw .invalidValueTag(tag)
            }
            let kind: SQLTableConstraintKind
            switch try reader.readUInt8() {
            case 0: kind = .primaryKey(columns: try readDDLStrings(from: &reader))
            case 1: kind = .unique(columns: try readDDLStrings(from: &reader), nulls: try decodeDDLNulls(from: &reader))
            case 2: kind = .notNull(column: try reader.readString())
            case 3: kind = .check(try decodeExpression(from: &reader))
            case 4:
                let columns = try readDDLStrings(from: &reader)
                let table = try decodeTableRef(from: &reader)
                let targets = try readDDLOptionalStrings(from: &reader)
                let match: SQLForeignKeyMatch
                switch try reader.readUInt8() {
                case 0: match = .simple
                case 1: match = .full
                case let tag: throw .invalidValueTag(tag)
                }
                kind = .foreignKey(SQLForeignKeyDefinition(columns: columns, referencedTable: table,
                    referencedColumns: targets, match: match, onUpdate: try decodeDDLReferentialAction(from: &reader),
                    onDelete: try decodeDDLReferentialAction(from: &reader), onDeleteColumns: try readDDLOptionalStrings(from: &reader)))
            case let tag: throw .invalidValueTag(tag)
            }
            return SQLTableConstraint(name: name, timing: timing, kind: kind)
        }
    }

    private static func encodeDDLAlterAction(_ value: SQLAlterTableAction, into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try writer.withNestedValue { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            switch value {
            case .addColumn(let column, let flag):
                writer.writeUInt8(0)
                try encodeDDLColumn(column, into: &writer)
                writer.writeBool(flag)
            case .dropColumn(let name, let flag, let behavior):
                writer.writeUInt8(1)
                try writer.writeString(name)
                writer.writeBool(flag)
                encodeDropBehavior(behavior, into: &writer)
            case .renameColumn(let name, let target):
                writer.writeUInt8(2)
                try writer.writeString(name)
                try writer.writeString(target)
            case .alterColumnType(let name, let type, let expression):
                writer.writeUInt8(3)
                try writer.writeString(name)
                try encodeDataType(type, into: &writer)
                try writeOptional(expression, into: &writer, encode: encodeExpression)
            case .setDefault(let column, let expression):
                writer.writeUInt8(4)
                try writer.writeString(column)
                try encodeExpression(expression, into: &writer)
            case .dropDefault(let column): writer.writeUInt8(5); try writer.writeString(column)
            case .setNotNull(let column): writer.writeUInt8(6); try writer.writeString(column)
            case .dropNotNull(let column): writer.writeUInt8(7); try writer.writeString(column)
            case .addConstraint(let constraint): writer.writeUInt8(8); try encodeDDLConstraint(constraint, into: &writer)
            case .dropConstraint(let name, let flag, let behavior):
                writer.writeUInt8(9)
                try writer.writeString(name)
                writer.writeBool(flag)
                encodeDropBehavior(behavior, into: &writer)
            case .renameTable(let name): writer.writeUInt8(10); try writer.writeString(name)
            }
        }
    }

    private static func decodeDDLAlterAction(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLAlterTableAction {
        try reader.withNestedValue { (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLAlterTableAction in
            switch try reader.readUInt8() {
            case 0: return .addColumn(try decodeDDLColumn(from: &reader), ifNotExists: try reader.readBool())
            case 1: return .dropColumn(name: try reader.readString(), ifExists: try reader.readBool(), behavior: try decodeDropBehavior(from: &reader))
            case 2: return .renameColumn(name: try reader.readString(), to: try reader.readString())
            case 3: return .alterColumnType(name: try reader.readString(), type: try decodeDataType(from: &reader), using: try readOptional(from: &reader, decode: decodeExpression))
            case 4: return .setDefault(column: try reader.readString(), expression: try decodeExpression(from: &reader))
            case 5: return .dropDefault(column: try reader.readString())
            case 6: return .setNotNull(column: try reader.readString())
            case 7: return .dropNotNull(column: try reader.readString())
            case 8: return .addConstraint(try decodeDDLConstraint(from: &reader))
            case 9: return .dropConstraint(name: try reader.readString(), ifExists: try reader.readBool(), behavior: try decodeDropBehavior(from: &reader))
            case 10: return .renameTable(to: try reader.readString())
            case let tag: throw .invalidValueTag(tag)
            }
        }
    }

    private static func encodeDDLSequenceOptions(_ value: SQLSequenceOptions, into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try writeOptional(value.type, into: &writer, encode: encodeDataType)
        try writeOptional(value.start, into: &writer) { value, writer in writer.writeInt64(value) }
        try writeOptional(value.increment, into: &writer) { value, writer in writer.writeInt64(value) }
        try writeOptional(value.minimum, into: &writer, encode: encodeDDLBound)
        try writeOptional(value.maximum, into: &writer, encode: encodeDDLBound)
        try writeOptional(value.cycle, into: &writer) { value, writer in writer.writeBool(value) }
    }

    private static func decodeDDLSequenceOptions(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLSequenceOptions {
        SQLSequenceOptions(type: try readOptional(from: &reader, decode: decodeDataType),
            start: try readOptional(from: &reader) { (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> Int64 in try reader.readInt64() },
            increment: try readOptional(from: &reader) { (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> Int64 in try reader.readInt64() },
            minimum: try readOptional(from: &reader, decode: decodeDDLBound),
            maximum: try readOptional(from: &reader, decode: decodeDDLBound),
            cycle: try readOptional(from: &reader) { (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> Bool in try reader.readBool() })
    }

    private static func encodeDDLBound(_ value: SQLSequenceBound, into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        switch value {
        case .value(let number): writer.writeUInt8(0); writer.writeInt64(number)
        case .none: writer.writeUInt8(1)
        }
    }

    private static func decodeDDLBound(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLSequenceBound {
        switch try reader.readUInt8() {
        case 0: return .value(try reader.readInt64())
        case 1: return .none
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodeDDLRestart(_ value: SQLSequenceRestart, into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        switch value {
        case .start: writer.writeUInt8(0)
        case .value(let number): writer.writeUInt8(1); writer.writeInt64(number)
        }
    }

    private static func decodeDDLRestart(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLSequenceRestart {
        switch try reader.readUInt8() {
        case 0: return .start
        case 1: return .value(try reader.readInt64())
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodeDDLOwnership(_ value: SQLSequenceOwnership, into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        switch value {
        case .none: writer.writeUInt8(0)
        case .column(let table, let column):
            writer.writeUInt8(1)
            try encodeTableRef(table, into: &writer)
            try writer.writeString(column)
        }
    }

    private static func decodeDDLOwnership(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLSequenceOwnership {
        switch try reader.readUInt8() {
        case 0: return .none
        case 1: return .column(table: try decodeTableRef(from: &reader), column: try reader.readString())
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodeDropBehavior(_ value: SQLDropBehavior, into writer: inout DatabaseWireWriter) {
        writer.writeUInt8(value == .restrict ? 0 : 1)
    }

    private static func decodeDropBehavior(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLDropBehavior {
        switch try reader.readUInt8() {
        case 0: return .restrict
        case 1: return .cascade
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodeDDLNulls(_ value: SQLNullUniqueness, into writer: inout DatabaseWireWriter) {
        writer.writeUInt8(value == .distinct ? 0 : 1)
    }

    private static func decodeDDLNulls(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLNullUniqueness {
        switch try reader.readUInt8() {
        case 0: return .distinct
        case 1: return .notDistinct
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodeDDLReferentialAction(_ value: SQLReferentialAction, into writer: inout DatabaseWireWriter) {
        switch value {
        case .noAction: writer.writeUInt8(0)
        case .restrict: writer.writeUInt8(1)
        case .cascade: writer.writeUInt8(2)
        case .setNull: writer.writeUInt8(3)
        case .setDefault: writer.writeUInt8(4)
        }
    }

    private static func decodeDDLReferentialAction(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLReferentialAction {
        switch try reader.readUInt8() {
        case 0: return .noAction
        case 1: return .restrict
        case 2: return .cascade
        case 3: return .setNull
        case 4: return .setDefault
        case let tag: throw .invalidValueTag(tag)
        }
    }


    // Count admission precedes growth; a truncated declared width never reserves absent children.
    private static func readDDLArray<Element>(
        from reader: inout DatabaseWireReader,
        decode: (inout DatabaseWireReader) throws(DatabaseWireError) -> Element
    ) throws(DatabaseWireError) -> [Element] {
        let count = try reader.readCount()
        var values: [Element] = []
        for _ in 0..<count { values.append(try decode(&reader)) }
        return values
    }

    private static func readDDLStrings(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> [String] {
        try readDDLArray(from: &reader) { (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> String in
            try reader.readString()
        }
    }

    private static func readDDLOptionalStrings(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> [String]? {
        try readOptional(from: &reader, decode: readDDLStrings)
    }
}
