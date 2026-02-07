import Core

/// A batch of changes to be applied atomically on the server
///
/// Mirrors the FDBContext change tracking pattern:
/// client accumulates insert/update/delete, then sends as a single ChangeSet on save().
public struct ChangeSet: Sendable, Codable {

    /// A single change operation
    public struct Change: Sendable, Codable {

        /// Type of change
        public enum Operation: String, Sendable, Codable {
            case insert
            case update
            case delete
        }

        /// Entity type name (Persistable.persistableType)
        public let entityName: String

        /// Record ID
        public let id: String

        /// Change operation
        public let operation: Operation

        /// Field values (nil for delete)
        public let fields: [String: FieldValue]?

        /// Partition values for dynamic directory types
        public let partitionValues: [String: String]?

        public init(
            entityName: String,
            id: String,
            operation: Operation,
            fields: [String: FieldValue]? = nil,
            partitionValues: [String: String]? = nil
        ) {
            self.entityName = entityName
            self.id = id
            self.operation = operation
            self.fields = fields
            self.partitionValues = partitionValues
        }
    }

    /// List of changes to apply
    public var changes: [Change]

    public init(changes: [Change] = []) {
        self.changes = changes
    }
}
