import DatabaseKit
import DatabaseTypes

enum SQLDiagnosticWireCodec {
    static func object(_ diagnostic: SQLDiagnostic) throws(DatabaseWireError) -> FieldObject {
        var fields: [(key: String, value: FieldValue)] = [
            ("sqlState", .string(diagnostic.sqlState)),
            ("category", .uint8(tag(diagnostic.category))),
            ("message", .string(diagnostic.message)),
        ]
        if let position = diagnostic.position { fields.append(("position", .uint64(position))) }
        if let schema = diagnostic.schema { fields.append(("schema", .string(schema))) }
        if let table = diagnostic.table { fields.append(("table", .string(table))) }
        if let column = diagnostic.column { fields.append(("column", .string(column))) }
        if let constraint = diagnostic.constraint { fields.append(("constraint", .string(constraint))) }
        do { return try FieldObject(fields) }
        catch { throw .invalidFieldObject(error) }
    }

    static func diagnostic(_ object: FieldObject) throws(DatabaseWireError) -> SQLDiagnostic {
        for field in object.fields {
            switch field.key {
            case "sqlState", "category", "message", "position", "schema", "table", "column", "constraint": break
            default: throw .invalidSQLDiagnostic
            }
        }
        guard case .string(let state) = object["sqlState"],
              case .uint8(let tag) = object["category"],
              case .string(let message) = object["message"] else { throw .invalidSQLDiagnostic }
        let position: UInt64?
        if let value = object["position"] {
            guard case .uint64(let count) = value, count > 0 else { throw .invalidSQLDiagnostic }
            position = count
        } else { position = nil }
        let category = try category(tag)
        let schema = try optionalString("schema", from: object)
        let table = try optionalString("table", from: object)
        let column = try optionalString("column", from: object)
        let constraint = try optionalString("constraint", from: object)
        do {
            return try SQLDiagnostic(sqlState: state, category: category, message: message,
                position: position, schema: schema, table: table, column: column, constraint: constraint)
        } catch { throw .invalidSQLDiagnostic }
    }

    private static func optionalString(_ key: String, from object: FieldObject)
    throws(DatabaseWireError) -> String? {
        guard let value = object[key] else { return nil }
        guard case .string(let string) = value else { throw .invalidSQLDiagnostic }
        return string
    }

    private static func tag(_ category: SQLDiagnosticCategory) -> UInt8 {
        switch category {
        case .syntax: 0
        case .name: 1
        case .type: 2
        case .cardinality: 3
        case .constraint: 4
        case .numeric: 5
        case .data: 6
        case .serialization: 7
        case .transaction: 8
        case .cancellation: 9
        case .unsupported: 10
        case .resource: 11
        case .authorization: 12
        case .internalError: 13
        }
    }

    private static func category(_ tag: UInt8) throws(DatabaseWireError) -> SQLDiagnosticCategory {
        switch tag {
        case 0: .syntax
        case 1: .name
        case 2: .type
        case 3: .cardinality
        case 4: .constraint
        case 5: .numeric
        case 6: .data
        case 7: .serialization
        case 8: .transaction
        case 9: .cancellation
        case 10: .unsupported
        case 11: .resource
        case 12: .authorization
        case 13: .internalError
        default: throw .invalidSQLDiagnostic
        }
    }
}
