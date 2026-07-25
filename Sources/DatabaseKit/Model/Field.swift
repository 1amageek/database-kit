import DatabaseTypes

/// The stable schema identity of a persisted field.
public struct FieldIdentity: Sendable, Hashable {
    public let name: String
    public let number: Int

    public init(name: String, number: Int) {
        self.name = name
        self.number = number
    }
}

/// A compile-time typed reference to a persisted field.
///
/// `Root` and `Value` are phantom types used by schema and query APIs. The
/// runtime representation contains only canonical schema metadata and never
/// retains a Swift key path or metatype.
public struct Field<Root, Value>: Sendable, Hashable {
    public let identity: FieldIdentity
    public let type: FieldSchemaType
    public let isOptional: Bool
    public let isArray: Bool
    public let referenceTargetEntity: String?

    public var name: String {
        identity.name
    }

    public var number: Int {
        identity.number
    }

    public var schema: FieldSchema {
        FieldSchema(
            name: identity.name,
            fieldNumber: identity.number,
            type: type,
            isOptional: isOptional,
            isArray: isArray,
            referenceTargetEntity: referenceTargetEntity
        )
    }

    public init(
        identity: FieldIdentity,
        type: FieldSchemaType,
        isOptional: Bool = false,
        isArray: Bool = false,
        referenceTargetEntity: String? = nil
    ) {
        self.identity = identity
        self.type = type
        self.isOptional = isOptional
        self.isArray = isArray
        self.referenceTargetEntity = referenceTargetEntity
    }
}
