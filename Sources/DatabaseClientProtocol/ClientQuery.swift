import Core
import QueryIR

// MARK: - Query (Unified)

/// Request payload for operationID: "query"
///
/// Accepts any QueryStatement (SELECT, INSERT, UPDATE, DELETE, etc.)
/// for full SQL/SPARQL query capability over the wire.
public struct QueryRequest: Sendable, Codable {
    /// The query statement to execute
    public let statement: QueryStatement

    /// Partition values for dynamic directory types
    public let partitionValues: [String: String]?

    public init(statement: QueryStatement, partitionValues: [String: String]? = nil) {
        self.statement = statement
        self.partitionValues = partitionValues
    }
}

/// Response payload for operationID: "query"
public struct QueryResponse: Sendable, Codable {
    /// Records as field-value dictionaries
    public let records: [[String: FieldValue]]

    /// Continuation token for next page (nil if no more pages)
    public let continuation: String?

    /// Number of affected rows (for INSERT/UPDATE/DELETE)
    public let affectedRows: Int?

    public init(
        records: [[String: FieldValue]] = [],
        continuation: String? = nil,
        affectedRows: Int? = nil
    ) {
        self.records = records
        self.continuation = continuation
        self.affectedRows = affectedRows
    }
}

// MARK: - Fetch

/// Request payload for operationID: "fetch"
public struct FetchRequest: Sendable, Codable {
    /// Entity type name (Persistable.persistableType)
    public let entityName: String

    /// Optional filter expression (QueryIR.Expression)
    public let predicate: Expression?

    /// Sort keys
    public let sortDescriptors: [SortKey]

    /// Maximum number of records to return
    public let limit: Int?

    /// Continuation token for pagination (base64-encoded)
    public let continuation: String?

    /// Partition values for dynamic directory types
    public let partitionValues: [String: String]?

    public init(
        entityName: String,
        predicate: Expression? = nil,
        sortDescriptors: [SortKey] = [],
        limit: Int? = nil,
        continuation: String? = nil,
        partitionValues: [String: String]? = nil
    ) {
        self.entityName = entityName
        self.predicate = predicate
        self.sortDescriptors = sortDescriptors
        self.limit = limit
        self.continuation = continuation
        self.partitionValues = partitionValues
    }
}

/// Response payload for operationID: "fetch"
public struct FetchResponse: Sendable, Codable {
    /// Records as field-value dictionaries
    public let records: [[String: FieldValue]]

    /// Continuation token for next page (nil if no more pages)
    public let continuation: String?

    public init(records: [[String: FieldValue]], continuation: String? = nil) {
        self.records = records
        self.continuation = continuation
    }
}

// MARK: - Get

/// Request payload for operationID: "get"
public struct GetRequest: Sendable, Codable {
    /// Entity type name
    public let entityName: String

    /// Record ID
    public let id: String

    /// Partition values for dynamic directory types
    public let partitionValues: [String: String]?

    public init(entityName: String, id: String, partitionValues: [String: String]? = nil) {
        self.entityName = entityName
        self.id = id
        self.partitionValues = partitionValues
    }
}

/// Response payload for operationID: "get"
public struct GetResponse: Sendable, Codable {
    /// Record as field-value dictionary (nil if not found)
    public let record: [String: FieldValue]?

    public init(record: [String: FieldValue]?) {
        self.record = record
    }
}

// MARK: - Save

/// Request payload for operationID: "save"
public struct SaveRequest: Sendable, Codable {
    /// Changes to apply atomically
    public let changes: [ChangeSet.Change]

    public init(changes: [ChangeSet.Change]) {
        self.changes = changes
    }
}

// MARK: - Count

/// Request payload for operationID: "count"
public struct CountRequest: Sendable, Codable {
    /// Entity type name
    public let entityName: String

    /// Optional filter expression (QueryIR.Expression)
    public let predicate: Expression?

    /// Partition values for dynamic directory types
    public let partitionValues: [String: String]?

    public init(entityName: String, predicate: Expression? = nil, partitionValues: [String: String]? = nil) {
        self.entityName = entityName
        self.predicate = predicate
        self.partitionValues = partitionValues
    }
}

/// Response payload for operationID: "count"
public struct CountResponse: Sendable, Codable {
    /// Number of matching records
    public let count: Int

    public init(count: Int) {
        self.count = count
    }
}

// MARK: - Schema

/// Response payload for operationID: "schema"
public struct SchemaResponse: Sendable, Codable {
    /// All registered entity definitions
    public let entities: [Schema.Entity]

    public init(entities: [Schema.Entity]) {
        self.entities = entities
    }
}
