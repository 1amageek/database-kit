import Core
import Foundation

/// Stable record identity used by client-server write contracts.
///
/// `partitionValues` keeps dynamic-directory records addressable without
/// encoding package-specific directory details into command payloads.
public struct RecordKey: Sendable, Codable, Hashable {
    public let entityName: String
    public let id: FieldValue
    public let partitionValues: [String: String]?

    public init(
        entityName: String,
        id: FieldValue,
        partitionValues: [String: String]? = nil
    ) {
        self.entityName = entityName
        self.id = id
        self.partitionValues = partitionValues
    }
}

/// Opaque record version returned by the server and supplied back by clients
/// for optimistic concurrency checks.
public struct RecordVersionToken: Sendable, Codable, Hashable {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }
}

/// Wire-safe write precondition kind.
public enum WritePreconditionKind: String, Sendable, Codable, Hashable {
    case none
    case notExists
    case exists
    case matchesStored
    case matchesStoredOrAbsent
}

/// Wire-safe write precondition.
///
/// Runtime-specific precondition types live in `database-framework`; this DTO
/// belongs to the protocol layer and carries only client-safe data.
public struct WritePreconditionSpec: Sendable, Codable, Hashable {
    public let kind: WritePreconditionKind
    public let version: RecordVersionToken?

    public init(
        kind: WritePreconditionKind,
        version: RecordVersionToken? = nil
    ) {
        self.kind = kind
        self.version = version
    }

    public static let none = WritePreconditionSpec(kind: .none)
    public static let notExists = WritePreconditionSpec(kind: .notExists)
    public static let exists = WritePreconditionSpec(kind: .exists)

    public static func matchesStored(_ version: RecordVersionToken) -> WritePreconditionSpec {
        WritePreconditionSpec(kind: .matchesStored, version: version)
    }

    public static func matchesStoredOrAbsent(_ version: RecordVersionToken) -> WritePreconditionSpec {
        WritePreconditionSpec(kind: .matchesStoredOrAbsent, version: version)
    }
}

/// Codable precondition entry.
///
/// This deliberately uses an array entry instead of `[RecordKey:
/// WritePreconditionSpec]` so the JSON shape remains stable and easy to consume
/// from non-Swift clients.
public struct WritePreconditionEntry: Sendable, Codable, Hashable {
    public let key: RecordKey
    public let precondition: WritePreconditionSpec

    public init(
        key: RecordKey,
        precondition: WritePreconditionSpec
    ) {
        self.key = key
        self.precondition = precondition
    }
}

/// Idempotency key supplied by clients for retry-safe mutating operations.
public struct IdempotencyKey: Sendable, Codable, Hashable, ExpressibleByStringLiteral {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public init(stringLiteral value: StringLiteralType) {
        self.value = value
    }
}

/// Observable effect produced by a server-side command.
public struct CommandEffect: Sendable, Codable, Hashable {
    public let kind: String
    public let key: RecordKey?
    public let metadata: [String: FieldValue]

    public init(
        kind: String,
        key: RecordKey? = nil,
        metadata: [String: FieldValue] = [:]
    ) {
        self.kind = kind
        self.key = key
        self.metadata = metadata
    }

    public static func recordVersionChanged(
        key: RecordKey,
        version: RecordVersionToken
    ) -> CommandEffect {
        CommandEffect(
            kind: CommandEffectKind.recordVersionChanged,
            key: key,
            metadata: ["version": .string(version.value)]
        )
    }
}

public enum CommandEffectKind {
    public static let recordVersionChanged = "record.versionChanged"
}

/// Request payload for command-style mutating operations.
///
/// Transport routing remains `ServiceEnvelope.operationID`; `commandID`
/// identifies the domain command resolved by a server-side registry.
public struct CommandRequest: Sendable, Codable {
    public let commandID: String
    public let idempotencyKey: IdempotencyKey?
    public let payload: Data
    public let preconditions: [WritePreconditionEntry]
    public let metadata: [String: String]

    public init(
        commandID: String,
        idempotencyKey: IdempotencyKey? = nil,
        payload: Data = Data(),
        preconditions: [WritePreconditionEntry] = [],
        metadata: [String: String] = [:]
    ) {
        self.commandID = commandID
        self.idempotencyKey = idempotencyKey
        self.payload = payload
        self.preconditions = preconditions
        self.metadata = metadata
    }
}

/// Response payload for command-style mutating operations.
public struct CommandResponse: Sendable, Codable {
    public let status: String
    public let payload: Data
    public let effects: [CommandEffect]
    public let replayed: Bool

    public init(
        status: String,
        payload: Data = Data(),
        effects: [CommandEffect] = [],
        replayed: Bool = false
    ) {
        self.status = status
        self.payload = payload
        self.effects = effects
        self.replayed = replayed
    }
}
