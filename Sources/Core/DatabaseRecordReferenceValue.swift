import DatabaseValue

/// A typed model value that stores a canonical record identity.
public protocol DatabaseRecordReferenceValue: Codable, Sendable {
    var recordIdentity: RecordIdentity { get }

    static func decodeDatabaseRecordReference(
        _ identity: RecordIdentity
    ) throws -> Self
}
