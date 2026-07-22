/// Converts a model identifier into the canonical database identity domain.
///
/// Conformance is a compile-time persistence contract. The declared type and
/// each produced value must agree so direct storage operations and DatabaseWire
/// operations resolve to the same physical key.
public protocol RecordIdentifier: Sendable, Hashable {
    static var recordIdentifierType: RecordIdentifierType { get }
    var recordIdentifierValue: RecordIdentifierValue { get }
}
