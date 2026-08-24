import DatabaseTypes

/// A single already-resolved canonical field used by generated default
/// adaptation. It reuses the same typed decoding overloads as ordinary input.
public struct PersistedFieldValueInput: PersistedFieldInput, Sendable {
    public typealias Failure = Never

    private let identity: FieldIdentity
    private let value: FieldValue
    private var wasConsumed: Bool

    init(identity: FieldIdentity, value: FieldValue) {
        self.identity = identity
        self.value = value
        self.wasConsumed = false
    }

    public mutating func readField(
        _ identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Never>) -> FieldValue? {
        guard identity == self.identity else {
            throw .adaptation(
                .invalidFieldIdentity(
                    entity: entity,
                    number: identity.number,
                    name: identity.name
                )
            )
        }
        guard !wasConsumed else { return nil }
        wasConsumed = true
        return value
    }

    public func finish(
        entity: String
    ) throws(PersistableDecodingFailure<Never>) {
        guard let number = UInt32(exactly: identity.number) else {
            throw .adaptation(
                .invalidFieldIdentity(
                    entity: entity,
                    number: identity.number,
                    name: identity.name
                )
            )
        }
        guard wasConsumed else {
            throw .adaptation(
                .unconsumedField(
                    entity: entity,
                    number: number,
                    name: identity.name
                )
            )
        }
    }
}
