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
/// // Automatic metadata via PersistableEnum conformance:
/// let metadata = Status._enumMetadata
/// // EnumMetadata(typeName: "Status", cases: ["active", "inactive", "pending"])
///
/// // Runtime extraction (used by @Persistable macro):
/// let metadata = EnumMetadata.extract(from: Status.self)
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

    /// Extract EnumMetadata from a type at runtime.
    ///
    /// Returns metadata if the type conforms to `_EnumMetadataProvider`
    /// (typically via `PersistableEnum`), nil otherwise.
    ///
    /// Used by `@Persistable` macro-generated `enumMetadata(for:)`.
    public static func extract(from type: Any.Type) -> EnumMetadata? {
        guard let provider = type as? any _EnumMetadataProvider.Type else {
            return nil
        }
        return provider._enumMetadata
    }
}

// MARK: - Enum Metadata Provider Protocol

/// Type-erased protocol for providing enum metadata at runtime.
///
/// This protocol has no associated types, making it usable as an existential
/// (`any _EnumMetadataProvider.Type`). Conform to `PersistableEnum` instead
/// of implementing this directly.
public protocol _EnumMetadataProvider {
    static var _enumMetadata: EnumMetadata { get }
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
/// The `@Persistable` macro generates `EnumMetadata.extract(from: Status.self)`
/// for fields whose type is not a known primitive. If the type conforms to
/// `PersistableEnum`, metadata is returned; otherwise `nil`.
public protocol PersistableEnum: Sendable, Codable, CaseIterable, RawRepresentable, _EnumMetadataProvider
    where RawValue: Sendable & Codable {}

extension PersistableEnum where RawValue == String {
    public static var _enumMetadata: EnumMetadata {
        EnumMetadata(
            typeName: String(describing: Self.self),
            cases: allCases.map(\.rawValue)
        )
    }
}

extension PersistableEnum where RawValue == Int {
    public static var _enumMetadata: EnumMetadata {
        EnumMetadata(
            typeName: String(describing: Self.self),
            cases: allCases.map { String($0.rawValue) }
        )
    }
}
