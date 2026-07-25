import DatabaseTypes

/// A schema-addressed field in the compiled representation of a model.
///
/// Field numbers belong to compiled persistence schemas. Primitive objects use
/// `FieldObject`, whose identity consists only of canonical string keys.
public struct PersistableField: Sendable, Hashable {
    public let number: UInt32
    public let name: String
    public let value: FieldValue

    public init(
        number: UInt32,
        name: String,
        value: FieldValue
    ) throws(PersistableFieldError) {
        guard number > 0 else {
            throw .invalidNumber(number)
        }
        guard !name.isEmpty else {
            throw .emptyName
        }
        self.number = number
        self.name = name
        self.value = value
    }

    init(
        validatedNumber number: UInt32,
        validatedName name: String,
        value: FieldValue
    ) {
        self.number = number
        self.name = name
        self.value = value
    }
}
