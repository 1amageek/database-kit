import DatabaseKit
import DatabaseWire

/// Strict, bounded native JSON representation of a resolved query column type.
public struct QueryColumnTypeJSONCodec: Sendable {
    public let limits: DatabaseWireLimits

    public init(limits: DatabaseWireLimits = .default) {
        self.limits = limits
    }

    public func encode(_ type: QueryColumnType) throws(SchemaJSONError) -> String {
        do {
            let output = JSONWriter.encode(try encode(type, path: "queryType"))
            guard output.utf8.count <= limits.maximumFrameBytes else {
                throw SchemaJSONError.outputTooLarge(
                    actual: output.utf8.count, maximum: limits.maximumFrameBytes
                )
            }
            // Apply the same object-member and JSON-depth budgets as decoding.
            _ = try parser.parse(output)
            return output
        } catch let error as SchemaJSONError {
            throw error
        } catch {
            throw .invalidValue(path: "queryType", reason: String(describing: error))
        }
    }

    public func decode(_ text: String) throws(SchemaJSONError) -> QueryColumnType {
        do {
            return try decode(parser.parse(text), path: "queryType")
        } catch let error as SchemaJSONError {
            throw error
        } catch {
            throw .invalidValue(path: "queryType", reason: String(describing: error))
        }
    }

    private var parser: JSONParser {
        JSONParser(maximumBytes: limits.maximumFrameBytes,
                   maximumDepth: limits.maximumNestingDepth,
                   maximumCollectionCount: limits.maximumCollectionCount)
    }

    func encode(_ type: QueryColumnType, path: String, depth: Int = 0) throws -> JSONValue {
        try requireDepth(depth)
        try validate(type, path: path)
        _ = try descriptorLimits(path: path)
        switch type {
        case .primitive(let type, let isArray):
            return .object([("kind", .string("primitive")),
                            ("type", .string(type.rawValue)), ("isArray", .bool(isArray))])
        case .sql(let type):
            return .object([("kind", .string("sql")),
                            ("type", try encodeDataType(type, depth: depth + 1))])
        }
    }

    func decode(_ node: JSONValue, path: String, depth: Int = 0) throws -> QueryColumnType {
        try requireDepth(depth)
        _ = try descriptorLimits(path: path)
        let object = try JSONObject(node, path: path)
        let kind = try object.required("kind").string(path: object.child("kind"))
        let type: QueryColumnType
        switch kind {
        case "primitive":
            try object.validateKeys(["kind", "type", "isArray"])
            let rawType = try object.required("type").string(path: object.child("type"))
            guard let primitive = FieldSchemaType(rawValue: rawType) else {
                throw SchemaJSONError.invalidValue(path: object.child("type"), reason: "Unknown primitive type")
            }
            type = .primitive(primitive, isArray: try object.required("isArray").bool(path: object.child("isArray")))
        case "sql":
            try object.validateKeys(["kind", "type"])
            type = .sql(try decodeDataType(object.required("type"), path: object.child("type"), depth: depth + 1))
        default:
            throw SchemaJSONError.invalidValue(path: object.child("kind"), reason: "Unknown query type kind")
        }
        try validate(type, path: path)
        return type
    }

    private func validate(_ type: QueryColumnType, path: String) throws(SchemaJSONError) {
        guard QueryValueValidator.accepts(.primitive(.null), type: type) else {
            throw .invalidQueryValue(path: path, cause: .incompatibleType)
        }
        do throws(QueryValueError) {
            try descriptorFootprint(type).validate(limits: descriptorValueLimits())
        } catch {
            throw .invalidQueryValue(path: path, cause: error)
        }
    }

    private func descriptorFootprint(_ type: QueryColumnType) throws(QueryValueError) -> QueryValueFootprint {
        if case .sql(.composite(let descriptor)) = type { return try descriptor.measure() }
        if case .sql(.array(let element)) = type {
            let child = try descriptorFootprint(.sql(element))
            func increment(_ value: UInt64) throws(QueryValueError) -> UInt64 {
                let result = value.addingReportingOverflow(1)
                guard !result.overflow else { throw .arithmeticOverflow }
                return result.partialValue
            }
            return QueryValueFootprint(nodeCount: try increment(child.nodeCount),
                collectionElementCount: try increment(child.collectionElementCount),
                retainedByteCount: child.retainedByteCount,
                maximumNestingDepth: try increment(child.maximumNestingDepth))
        }
        return QueryValueFootprint(nodeCount: 1, collectionElementCount: 0,
            retainedByteCount: 0, maximumNestingDepth: 1)
    }

    private func encodeDataType(_ type: DataType, depth: Int) throws -> JSONValue {
        try requireDepth(depth)
        let kind: String
        var members: [(key: String, value: JSONValue)] = []
        switch type {
        case .boolean: kind = "boolean"
        case .smallint: kind = "smallint"
        case .integer: kind = "integer"
        case .bigint: kind = "bigint"
        case .real: kind = "real"
        case .doublePrecision: kind = "doublePrecision"
        case .text: kind = "text"
        case .date: kind = "date"
        case .interval(let fields, let precision):
            kind = "interval"
            members = [("fields", fields.map { .string($0.rawValue) } ?? .null), ("precision", optionalInteger(precision))]
        case .blob: kind = "blob"
        case .json: kind = "json"
        case .jsonb: kind = "jsonb"
        case .uuid: kind = "uuid"
        case .decimal(let precision, let scale):
            kind = "decimal"
            members = [("precision", optionalInteger(precision)), ("scale", optionalInteger(scale))]
        case .char(let length): kind = "char"; members = [("length", optionalInteger(length))]
        case .varchar(let length): kind = "varchar"; members = [("length", optionalInteger(length))]
        case .binary(let length): kind = "binary"; members = [("length", optionalInteger(length))]
        case .varbinary(let length): kind = "varbinary"; members = [("length", optionalInteger(length))]
        case .time(let withTimeZone, let precision):
            kind = "time"
            members = [("withTimeZone", .bool(withTimeZone)), ("precision", optionalInteger(precision))]
        case .timestamp(let withTimeZone, let precision):
            kind = "timestamp"
            members = [("withTimeZone", .bool(withTimeZone)), ("precision", optionalInteger(precision))]
        case .array(let element):
            kind = "array"
            members = [("element", try encodeDataType(element, depth: depth + 1))]
        case .composite(let descriptor):
            kind = "composite"
            do throws(QueryValueError) {
                try descriptor.measure().validate(limits: try descriptorValueLimits())
            } catch {
                throw SchemaJSONError.invalidQueryValue(path: "queryType", cause: error)
            }
            try SchemaJSONCodec(limits: limits).requireCollection(descriptor.columns.count, path: "columns")
            members = [("columns", .array(try descriptor.columns.enumerated().map { index, column in
                .object([("number", .number(String(column.number))),
                         ("name", .string(column.name)),
                         ("type", try encode(column.type, path: "columns[\(index)].type", depth: depth + 3)),
                         ("isNullable", .bool(column.isNullable))])
            }))]
        case .custom(let name, let schema):
            kind = "custom"
            members = [("name", .string(name)), ("schema", schema.map { .string($0) } ?? .null)]
        }
        return .object([("kind", .string(kind))] + members)
    }

    private func decodeDataType(_ node: JSONValue, path: String, depth: Int) throws -> DataType {
        try requireDepth(depth)
        let object = try JSONObject(node, path: path)
        let kind = try object.required("kind").string(path: object.child("kind"))
        let type: DataType
        switch kind {
        case "boolean": type = .boolean
        case "smallint": type = .smallint
        case "integer": type = .integer
        case "bigint": type = .bigint
        case "real": type = .real
        case "doublePrecision": type = .doublePrecision
        case "text": type = .text
        case "date": type = .date
        case "interval":
            try object.validateKeys(["kind", "fields", "precision"])
            let fieldsNode = try object.required("fields")
            let fields: SQLIntervalFields?
            if case .null = fieldsNode { fields = nil }
            else {
                let name = try fieldsNode.string(path: object.child("fields"))
                guard let value = SQLIntervalFields(rawValue: name) else {
                    throw SchemaJSONError.invalidValue(path: object.child("fields"), reason: "Unknown interval fields")
                }
                fields = value
            }
            return .interval(fields: fields, precision: try optionalInteger(object, "precision"))
        case "blob": type = .blob
        case "json": type = .json
        case "jsonb": type = .jsonb
        case "uuid": type = .uuid
        case "decimal":
            try object.validateKeys(["kind", "precision", "scale"])
            return .decimal(precision: try optionalInteger(object, "precision"), scale: try optionalInteger(object, "scale"))
        case "char", "varchar", "binary", "varbinary":
            try object.validateKeys(["kind", "length"])
            let length = try optionalInteger(object, "length")
            switch kind {
            case "char": return .char(length: length)
            case "varchar": return .varchar(length: length)
            case "binary": return .binary(length: length)
            default: return .varbinary(length: length)
            }
        case "time", "timestamp":
            try object.validateKeys(["kind", "withTimeZone", "precision"])
            let zone = try object.required("withTimeZone").bool(path: object.child("withTimeZone"))
            let precision = try optionalInteger(object, "precision")
            return kind == "time" ? .time(withTimeZone: zone, precision: precision)
                : .timestamp(withTimeZone: zone, precision: precision)
        case "array":
            try object.validateKeys(["kind", "element"])
            return .array(try decodeDataType(object.required("element"), path: object.child("element"), depth: depth + 1))
        case "composite":
            try object.validateKeys(["kind", "columns"])
            let columnsPath = object.child("columns")
            let nodes = try object.required("columns").array(path: columnsPath)
            try SchemaJSONCodec(limits: limits).requireCollection(nodes.count, path: columnsPath)
            let columns = try nodes.enumerated().map { index, node in
                let column = try JSONObject(node, path: "\(columnsPath)[\(index)]")
                try column.validateKeys(["number", "name", "type", "isNullable"])
                let number: UInt32 = try SchemaJSONCodec(limits: limits).integer(column, "number")
                do {
                    return try QueryColumn(number: number,
                        name: column.required("name").string(path: column.child("name")),
                        type: decode(column.required("type"), path: column.child("type"), depth: depth + 3),
                        isNullable: column.required("isNullable").bool(path: column.child("isNullable")))
                } catch let cause as QueryValueError {
                    throw SchemaJSONError.invalidQueryValue(path: "\(columnsPath)[\(index)]", cause: cause)
                }
            }
            do throws(QueryValueError) {
                return .composite(try QueryCompositeType(columns: columns, limits: descriptorValueLimits()))
            } catch {
                throw SchemaJSONError.invalidQueryValue(path: path, cause: error)
            }
        case "custom":
            try object.validateKeys(["kind", "name", "schema"])
            let schemaNode = try object.required("schema")
            let schema: String?
            if case .null = schemaNode { schema = nil }
            else { schema = try schemaNode.string(path: object.child("schema")) }
            return .custom(try object.required("name").string(path: object.child("name")), schema: schema)
        default:
            throw SchemaJSONError.invalidValue(path: object.child("kind"), reason: "Unknown SQL type")
        }
        try object.validateKeys(["kind"])
        return type
    }

    private func descriptorValueLimits() throws(QueryValueError) -> QueryValueLimits {
        let storage = try QueryCompositeType.constructionByteCount(
            typeNodeCapacity: limits.maximumObjectCount,
            columnCapacity: limits.maximumObjectCount)
        let retained = storage.addingReportingOverflow(UInt64(limits.maximumFrameBytes))
        guard !retained.overflow else { throw .arithmeticOverflow }
        return QueryValueLimits(maximumRetainedBytes: retained.partialValue,
            maximumTotalNodes: UInt64(limits.maximumObjectCount),
            maximumNestingDepth: UInt64(limits.maximumNestingDepth),
            maximumCollectionElements: UInt64(limits.maximumObjectCount))
    }

    private func descriptorLimits(path: String) throws(SchemaJSONError) -> QueryValueLimits {
        do throws(QueryValueError) { return try descriptorValueLimits() }
        catch { throw .invalidQueryValue(path: path, cause: error) }
    }

    private func requireDepth(_ depth: Int) throws(SchemaJSONError) {
        guard depth <= limits.maximumNestingDepth else {
            throw .nestingTooDeep(maximum: limits.maximumNestingDepth)
        }
    }

    private func optionalInteger(_ value: Int?) -> JSONValue {
        value.map { .number(String($0)) } ?? .null
    }

    private func optionalInteger(_ object: JSONObject, _ key: String) throws -> Int? {
        let node = try object.required(key)
        if case .null = node { return nil }
        return try SchemaJSONCodec(limits: limits).integer(node, path: object.child(key))
    }
}
