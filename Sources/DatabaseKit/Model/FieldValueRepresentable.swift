import DatabaseTypes

/// A value with a total, canonical representation as one `FieldValue`.
///
/// Unlike general model encoding, this conversion cannot fail. Query builders
/// use this stronger contract so every constructed predicate contains a valid
/// canonical value immediately.
public protocol FieldValueRepresentable: Sendable {
    var fieldValue: FieldValue { get }
}

extension FieldValueRepresentable {
    public func encodeFieldValue() -> FieldValue {
        fieldValue
    }
}
