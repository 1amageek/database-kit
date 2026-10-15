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

    func encode(_ type: QueryColumnType, path: String) throws -> JSONValue {
        try validate(type, path: path)
        switch type {
        case .primitive(let type, let isArray):
            return .object([("kind", .string("primitive")),
                            ("type", .string(type.rawValue)), ("isArray", .bool(isArray))])
        case .sql(let type):
            return .object([("kind", .string("sql")),
                            ("type", try encodeDataType(type, depth: 1))])
        }
    }

    func decode(_ node: JSONValue, path: String) throws -> QueryColumnType {
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
            type = .sql(try decodeDataType(object.required("type"), path: object.child("type"), depth: 1))
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
        case .interval: kind = "interval"
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
        case "interval": type = .interval
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
