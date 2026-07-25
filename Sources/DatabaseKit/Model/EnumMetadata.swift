import DatabaseTypes
/// Metadata for enum types
///
/// Provides information about enum cases for serialization and validation.
///
/// **Usage**:
/// ```swift
/// enum Status: String, PersistableEnum {
///     case active
///     case inactive
///     case pending
/// }
///
/// `@Persistable` supplies the stable source type name while the concrete enum
/// supplies its cases. No runtime metatype cast is involved.
/// ```
public struct EnumMetadata: Sendable, Equatable {
    /// The type name of the enum
    public let typeName: String

    /// All case names in the enum
    public let cases: [String]

    /// Initialize EnumMetadata
    ///
    /// - Parameters:
    ///   - typeName: The enum type name
    ///   - cases: All case names
    public init(typeName: String, cases: [String]) {
        self.typeName = typeName
        self.cases = cases
    }

    /// Check if a value is a valid case
    ///
    /// - Parameter value: The case name to validate
    /// - Returns: true if the value is a valid case
    public func isValidCase(_ value: String) -> Bool {
        return cases.contains(value)
    }

}

// MARK: - PersistableEnum Protocol

/// Protocol for enum types used as fields in `@Persistable` models.
///
/// Conforming enums automatically provide `EnumMetadata` for the schema catalog,
/// enabling CLI tools to display valid cases and validate values.
///
/// **Usage**:
/// ```swift
/// enum Status: String, PersistableEnum {
///     case active, inactive, pending
/// }
/// ```
///
/// The `@Persistable` macro invokes this concrete type's static field-value
/// contract. String- and Int-backed enums provide canonical case metadata.
public protocol PersistableEnum:
    FieldValueEncodable,
    CaseIterable,
    RawRepresentable
where RawValue: FieldValueEncodable & FieldValueDecodable {}

extension PersistableEnum where RawValue == String {
    public static var fieldSchemaType: FieldSchemaType { .enum }

    public static func fieldEnumMetadata(
        named typeName: String
    ) -> EnumMetadata? {
        EnumMetadata(
            typeName: typeName,
            cases: allCases.map { $0.rawValue }
        )
    }

    public func encodeFieldValue() -> FieldValue {
        .string(rawValue)
    }
}

extension PersistableEnum where RawValue == Int {
    public static var fieldSchemaType: FieldSchemaType { .enum }

    public static func fieldEnumMetadata(
        named typeName: String
    ) -> EnumMetadata? {
        EnumMetadata(
            typeName: typeName,
            cases: allCases.map { String($0.rawValue) }
        )
    }

    public func encodeFieldValue() -> FieldValue {
        .int64(Int64(rawValue))
    }
}
