import DatabaseTypes

/// A database entity value that exposes its canonical persisted fields without
/// requiring a concrete Swift model type.
///
/// Compiled `Persistable` values and type-independent `PersistedModel` values
/// share this boundary so execution layers can use one field-access path after
/// a model crosses into canonical persistence.
public protocol PersistedEntityValue: Sendable {
    /// The canonical schema entity name represented by this value.
    var persistedEntityName: String { get }

    /// Returns one canonical field value by schema field name.
    func persistedValue(
        forFieldNamed name: String
    ) throws(PersistableEncodingError) -> FieldValue?
}
