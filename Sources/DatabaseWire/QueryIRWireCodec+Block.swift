import DatabaseKit
import DatabaseTypes

extension QueryIRWireFormat {
    /// Encodes an operational request without changing ordinary statement tags.
    public static func encode(_ block: SQLBlock, limits: DatabaseWireLimits = .default)
    throws(DatabaseWireError) -> ByteString {
        return try DatabaseWireWriter.encode(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try encodeBlock(block, into: &writer)
        }
    }

    public static func emitCanonicalEncoding<DestinationFailure: Error>(
        _ block: SQLBlock, limits: DatabaseWireLimits = .default,
        prepare: (Int) throws(DestinationFailure) -> Void,
        consume: (UnsafeRawBufferPointer) -> Void
    ) throws(DatabaseWireEmissionError<DestinationFailure>) {
        try DatabaseWireWriter.emit(limits: limits, prepare: prepare, consume: consume) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try encodeBlock(block, into: &writer)
        }
    }

    public static func decodeBlock(_ bytes: ByteString, limits: DatabaseWireLimits = .default)
    throws(DatabaseWireError) -> SQLBlock {
        var reader = DatabaseWireReader(bytes, limits: limits)
        let block = try decodeBlock(from: &reader)
        try reader.ensureFullyRead()
        return block
    }

    static func decodeBlock(from reader: inout DatabaseWireReader)
    throws(DatabaseWireError) -> SQLBlock {
        guard try reader.readUInt8() == 0x42 else { throw .invalidMagic }
        try reader.beginNestedValue()
        let count = try reader.readCount()
        var steps: [SQLBlockStep] = []
        steps.reserveCapacity(count)
        for _ in 0..<count { steps.append(try decodeBlockStep(from: &reader)) }
        try reader.endNestedValue()
        do { return try SQLBlock(steps: steps, limits: blockLimits(reader.limits)) }
        catch { throw .invalidQueryStructure(error) }
    }

    private static func blockLimits(_ limits: DatabaseWireLimits) -> QueryStructuralLimits {
        QueryStructuralLimits(maximumNestingDepth: UInt64(limits.maximumNestingDepth),
            maximumRetainedBytes: UInt64(limits.maximumFrameBytes),
            maximumTotalNodes: UInt64(limits.maximumObjectCount),
            maximumCollectionElements: UInt64(limits.maximumObjectCount))
    }

    private static func validateBlock(_ block: SQLBlock, limits: DatabaseWireLimits) throws(DatabaseWireError) {
        do { try QueryStructuralValidator.validate(block, limits: blockLimits(limits)) }
        catch { throw .invalidQueryStructure(error) }
    }

    static func encodeBlock(_ block: SQLBlock, into writer: inout DatabaseWireWriter)
    throws(DatabaseWireError) {
        try validateBlock(block, limits: writer.limits)
        writer.writeUInt8(0x42)
        try writer.beginNestedValue()
        defer { writer.abandonNestedValues(1) }
        try writer.writeCount(block.steps.count)
        for step in block.steps {
            try writer.beginNestedValue()
            try encodeBlockStep(step, into: &writer)
            try writer.endNestedValue()
        }
    }

    private static func encodeBlockStep(_ step: SQLBlockStep, into writer: inout DatabaseWireWriter)
    throws(DatabaseWireError) {
        switch step {
        case .statement(let statement): writer.writeUInt8(0); try encodeStatement(statement, into: &writer)
        case .savepoint(let name): writer.writeUInt8(1); try writer.writeString(name)
        case .rollbackTo(let name): writer.writeUInt8(2); try writer.writeString(name)
        case .release(let name): writer.writeUInt8(3); try writer.writeString(name)
        case .setConstraints(let command):
            writer.writeUInt8(4)
            switch command.selection {
            case .all: writer.writeUInt8(0)
            case .named(let names): writer.writeUInt8(1); try writeStrings(names, into: &writer)
            }
            writer.writeBool(command.deferred)
        case .sequence(let command):
            writer.writeUInt8(5)
            switch command {
            case .create(let sequence): writer.writeUInt8(0); try encodeBlockSequence(sequence, into: &writer)
            case .alter(let sequence, let restart):
                writer.writeUInt8(1); try encodeBlockSequence(sequence, into: &writer)
                try writeOptional(restart, into: &writer) { value, writer in writer.writeInt64(value) }
            case .drop(let id, let cascade):
                writer.writeUInt8(2); try writer.writeString(id); writer.writeBool(cascade)
            }
        case .transaction(let control):
            writer.writeUInt8(6)
            switch control { case .begin: writer.writeUInt8(0); case .commit: writer.writeUInt8(1); case .rollback: writer.writeUInt8(2) }
        case .setting(let command):
            writer.writeUInt8(7)
            switch command {
            case .set(let name, let value, let scope):
                writer.writeUInt8(0); encodeSettingName(name, into: &writer)
                writer.writeUInt8(scope == .local ? 0 : 1); try encodeExpression(value, into: &writer)
            case .show(let name):
                writer.writeUInt8(1)
                try writeOptional(name, into: &writer, encode: encodeSettingName)
            case .reset(let name, let scope):
                writer.writeUInt8(2)
                try writeOptional(name, into: &writer, encode: encodeSettingName)
                writer.writeUInt8(scope == .local ? 0 : 1)
            }
        case .prepare(let command):
            writer.writeUInt8(8); try writer.writeString(command.name)
            try writeArray(command.parameterTypes, into: &writer, encode: encodeDataType)
            try encodeStatement(command.statement, into: &writer)
        case .execute(let command):
            writer.writeUInt8(9); try writer.writeString(command.name)
            try writeArray(command.arguments, into: &writer, encode: encodeExpression)
        case .deallocate(let name): writer.writeUInt8(10); try writeOptionalString(name, into: &writer)
        case .explain(let command):
            writer.writeUInt8(11); writer.writeBool(command.options.analyze); writer.writeBool(command.options.verbose)
            writer.writeUInt8(command.options.format == .text ? 0 : 1)
            try encodeStatement(command.statement, into: &writer)
        case .copy(let command):
            writer.writeUInt8(12)
            switch command.target {
            case .table(let table, let columns):
                writer.writeUInt8(0); try encodeTableRef(table, into: &writer); try writeStrings(columns, into: &writer)
            case .query(let query): writer.writeUInt8(1); try encodeSelectQuery(query, into: &writer)
            }
            writer.writeUInt8(command.direction == .from ? 0 : 1)
            writer.writeUInt8(command.options.format == .text ? 0 : 1)
            try writer.writeString(command.options.delimiter); try writer.writeString(command.options.null)
            writer.writeBool(command.options.header)
            try writer.writeString(command.options.quote); try writer.writeString(command.options.escape)
            try writeOptional(command.data, into: &writer) {
                (value: ByteString, writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                try writer.writeBytes(value)
            }
        }
    }

    private static func decodeBlockStep(from reader: inout DatabaseWireReader)
    throws(DatabaseWireError) -> SQLBlockStep {
        try reader.beginNestedValue()
        defer { reader.abandonNestedValues(1) }
        switch try reader.readUInt8() {
        case 0: return .statement(try decodeStatement(from: &reader))
        case 1: return .savepoint(try reader.readString())
        case 2: return .rollbackTo(try reader.readString())
        case 3: return .release(try reader.readString())
        case 4:
            let selection: SQLConstraintSelection
            switch try reader.readUInt8() {
            case 0: selection = .all
            case 1: selection = .named(try readStrings(from: &reader))
            case let tag: throw .invalidValueTag(tag)
            }
            let deferred = try reader.readBool()
            do { return .setConstraints(try SQLSetConstraints(selection: selection, deferred: deferred)) }
            catch { throw .invalidQueryIRWireState }
        case 5:
            switch try reader.readUInt8() {
            case 0: return .sequence(.create(try decodeBlockSequence(from: &reader)))
            case 1:
                let sequence = try decodeBlockSequence(from: &reader)
                let restart: Int64? = try readOptional(from: &reader) {
                    (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> Int64 in
                    try reader.readInt64()
                }
                return .sequence(.alter(sequence, restart: restart))
            case 2:
                let id = try reader.readString(); return .sequence(.drop(id: id, cascade: try reader.readBool()))
            case let tag: throw .invalidValueTag(tag)
            }
        case 6:
            switch try reader.readUInt8() {
            case 0: return .transaction(.begin)
            case 1: return .transaction(.commit)
            case 2: return .transaction(.rollback)
            case let tag: throw .invalidValueTag(tag)
            }
        case 7:
            switch try reader.readUInt8() {
            case 0:
                let name = try decodeSettingName(from: &reader)
                let scope = try decodeSettingScope(from: &reader)
                return .setting(.set(name: name, value: try decodeExpression(from: &reader), scope: scope))
            case 1:
                return .setting(.show(try readOptional(from: &reader, decode: decodeSettingName)))
            case 2:
                let name: SQLSettingName? = try readOptional(from: &reader, decode: decodeSettingName)
                return .setting(.reset(name, scope: try decodeSettingScope(from: &reader)))
            case let tag: throw .invalidValueTag(tag)
            }
        case 8:
            let name = try reader.readString()
            let types = try readArray(from: &reader, decode: decodeDataType)
            return .prepare(SQLPrepare(name: name, parameterTypes: types, statement: try decodeStatement(from: &reader)))
        case 9:
            let name = try reader.readString()
            let arguments = try readArray(from: &reader, decode: decodeExpression)
            return .execute(SQLExecute(name: name, arguments: arguments))
        case 10: return .deallocate(try readOptionalString(from: &reader))
        case 11:
            let analyze = try reader.readBool(); let verbose = try reader.readBool()
            let format: SQLExplainFormat
            switch try reader.readUInt8() {
            case 0: format = .text
            case 1: format = .json
            case let tag: throw .invalidValueTag(tag)
            }
            return .explain(SQLExplain(statement: try decodeStatement(from: &reader),
                options: SQLExplainOptions(analyze: analyze, verbose: verbose, format: format)))
        case 12: return .copy(try decodeBlockCopy(from: &reader))
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodeSettingName(_ name: SQLSettingName, into writer: inout DatabaseWireWriter) {
        switch name { case .searchPath: writer.writeUInt8(0); case .timeZone: writer.writeUInt8(1); case .statementTimeout: writer.writeUInt8(2) }
    }
    private static func decodeSettingName(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLSettingName {
        switch try reader.readUInt8() {
        case 0: return .searchPath
        case 1: return .timeZone
        case 2: return .statementTimeout
        case let tag: throw .invalidValueTag(tag)
        }
    }
    private static func decodeSettingScope(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLSettingScope {
        switch try reader.readUInt8() {
        case 0: return .local
        case 1: return .session
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func decodeBlockCopy(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLCopyCommand {
        let target: SQLCopyTarget
        switch try reader.readUInt8() {
        case 0:
            let table = try decodeTableRef(from: &reader)
            target = .table(table, columns: try readStrings(from: &reader))
        case 1: target = .query(try decodeSelectQuery(from: &reader))
        case let tag: throw .invalidValueTag(tag)
        }
        let direction: SQLCopyDirection
        switch try reader.readUInt8() { case 0: direction = .from; case 1: direction = .to; case let tag: throw .invalidValueTag(tag) }
        let format: SQLCopyFormat
        switch try reader.readUInt8() { case 0: format = .text; case 1: format = .csv; case let tag: throw .invalidValueTag(tag) }
        let delimiter = try reader.readString(); let null = try reader.readString()
        let header = try reader.readBool(); let quote = try reader.readString(); let escape = try reader.readString()
        let data: ByteString? = try readOptional(from: &reader) {
            (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> ByteString in
            try reader.readBytes()
        }
        let options: SQLCopyOptions
        do throws(QueryStructuralValidationError) {
            if format == .text {
                guard quote == "\"", escape == "\"" else { throw QueryStructuralValidationError.invalidSQLControl }
                options = try SQLCopyOptions(format: format, delimiter: delimiter, null: null, header: header)
            } else {
                options = try SQLCopyOptions(format: format, delimiter: delimiter, null: null, header: header, quote: quote, escape: escape)
            }
        } catch { throw .invalidQueryStructure(error) }
        return SQLCopyCommand(target: target, direction: direction, options: options, data: data)
    }

    private static func encodeBlockSequence(_ sequence: SQLSequence, into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try writer.writeString(sequence.id); try writer.writeString(sequence.namespaceID); try writer.writeString(sequence.name)
        writer.writeInt64(sequence.start); writer.writeInt64(sequence.increment)
        writer.writeInt64(sequence.minimum); writer.writeInt64(sequence.maximum); writer.writeBool(sequence.cycle)
        try writeOptional(sequence.ownedBy, into: &writer) {
            (owner: SQLSequenceOwner, writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writer.writeString(owner.relationID); try writer.writeString(owner.columnID)
        }
        try encodeDataType(sequence.declaredType, into: &writer)
    }
    private static func decodeBlockSequence(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLSequence {
        let id = try reader.readString(); let namespace = try reader.readString(); let name = try reader.readString()
        let start = try reader.readInt64(); let increment = try reader.readInt64()
        let minimum = try reader.readInt64(); let maximum = try reader.readInt64(); let cycle = try reader.readBool()
        let ownedBy: SQLSequenceOwner? = try readOptional(from: &reader) {
            (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLSequenceOwner in
            let relation = try reader.readString(); let column = try reader.readString()
            do { return try SQLSequenceOwner(relationID: relation, columnID: column) }
            catch { throw .invalidQueryIRWireState }
        }
        let type = try decodeDataType(from: &reader)
        do { return try SQLSequence(id: id, namespaceID: namespace, name: name, start: start,
            increment: increment, minimum: minimum, maximum: maximum, cycle: cycle, ownedBy: ownedBy, declaredType: type) }
        catch { throw .invalidQueryIRWireState }
    }
}
