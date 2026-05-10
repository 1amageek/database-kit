import Core
import QueryIR

// MARK: - Query Continuation

/// Opaque continuation token for paginated read queries.
public struct QueryContinuation: Sendable, Codable, Hashable {
    public let token: String

    public init(_ token: String) {
        self.token = token
    }
}

// MARK: - Read Execution Options

/// Read consistency hint for canonical query execution.
///
/// Defaults are chosen by `database-framework` binders/executors.
public enum ReadConsistency: String, Sendable, Codable, Hashable {
    case serializable
    case snapshot
}

/// Execution options for canonical read queries.
public struct ReadExecutionOptions: Sendable, Codable, Hashable {
    public let consistency: ReadConsistency?
    public let pageSize: Int?
    public let continuation: QueryContinuation?

    public init(
        consistency: ReadConsistency? = nil,
        pageSize: Int? = nil,
        continuation: QueryContinuation? = nil
    ) {
        self.consistency = consistency
        self.pageSize = pageSize
        self.continuation = continuation
    }

    public static let `default` = ReadExecutionOptions()
}

// MARK: - Query Row

/// Canonical row representation returned over the wire.
public struct QueryRow: Sendable, Codable, Hashable {
    public let fields: [String: FieldValue]
    public let annotations: [String: FieldValue]
    public let version: RecordVersionToken?

    public init(
        fields: [String: FieldValue],
        annotations: [String: FieldValue] = [:],
        version: RecordVersionToken? = nil
    ) {
        self.fields = fields
        self.annotations = annotations
        self.version = version
    }
}

// MARK: - Query Request / Response

/// Request payload for operationID: "query".
public struct QueryRequest: Sendable, Codable {
    public let statement: QueryStatement
    public let options: ReadExecutionOptions
    public let partitionValues: [String: String]?

    public init(
        statement: QueryStatement,
        options: ReadExecutionOptions = .default,
        partitionValues: [String: String]? = nil
    ) {
        self.statement = statement
        self.options = options
        self.partitionValues = partitionValues
    }
}

/// Response payload for operationID: "query".
public struct QueryResponse: Sendable, Codable {
    public let rows: [QueryRow]
    public let continuation: QueryContinuation?
    public let metadata: [String: FieldValue]
    public let affectedRows: Int?

    public init(
        rows: [QueryRow] = [],
        continuation: QueryContinuation? = nil,
        metadata: [String: FieldValue] = [:],
        affectedRows: Int? = nil
    ) {
        self.rows = rows
        self.continuation = continuation
        self.metadata = metadata
        self.affectedRows = affectedRows
    }
}

// MARK: - Save

/// Request payload for operationID: "save".
public struct SaveRequest: Sendable, Codable {
    public let changes: [ChangeSet.Change]
    public let preconditions: [WritePreconditionEntry]
    public let idempotencyKey: IdempotencyKey?
    public let clientMutationID: String?

    private enum CodingKeys: String, CodingKey {
        case changes
        case preconditions
        case idempotencyKey
        case clientMutationID
    }

    public init(
        changes: [ChangeSet.Change],
        preconditions: [WritePreconditionEntry] = [],
        idempotencyKey: IdempotencyKey? = nil,
        clientMutationID: String? = nil
    ) {
        self.changes = changes
        self.preconditions = preconditions
        self.idempotencyKey = idempotencyKey
        self.clientMutationID = clientMutationID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.changes = try container.decode([ChangeSet.Change].self, forKey: .changes)
        self.preconditions = try container.decodeIfPresent(
            [WritePreconditionEntry].self,
            forKey: .preconditions
        ) ?? []
        self.idempotencyKey = try container.decodeIfPresent(
            IdempotencyKey.self,
            forKey: .idempotencyKey
        )
        self.clientMutationID = try container.decodeIfPresent(
            String.self,
            forKey: .clientMutationID
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(changes, forKey: .changes)
        if !preconditions.isEmpty {
            try container.encode(preconditions, forKey: .preconditions)
        }
        try container.encodeIfPresent(idempotencyKey, forKey: .idempotencyKey)
        try container.encodeIfPresent(clientMutationID, forKey: .clientMutationID)
    }
}

// MARK: - Schema

/// Response payload for operationID: "schema".
public struct SchemaResponse: Sendable, Codable {
    public let entities: [Schema.Entity]
    public let polymorphicGroups: [PolymorphicGroup]

    public init(
        entities: [Schema.Entity],
        polymorphicGroups: [PolymorphicGroup] = []
    ) {
        self.entities = entities
        self.polymorphicGroups = polymorphicGroups
    }
}
