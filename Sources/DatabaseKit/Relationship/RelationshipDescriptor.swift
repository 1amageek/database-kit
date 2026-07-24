
/// Runtime metadata for a typed entity relationship.
public struct RelationshipDescriptor: RuntimeMaintainedDescriptor, Sendable {
    public let ownerTypeName: String
    public let propertyName: String
    public let propertyFieldNumber: UInt32
    public let relatedTypeName: String
    public let cardinality: RelationshipCardinality
    public let deleteRule: DeleteRule

    public var name: String {
        "\(ownerTypeName).\(propertyName)"
    }

    public var runtimeMaintainerIdentifier: String {
        "relationship.reference"
    }

    public var isToMany: Bool {
        cardinality == .toMany
    }

    public var isToOne: Bool {
        !isToMany
    }

    public var isOptional: Bool {
        cardinality == .optionalToOne
    }

    public init(
        ownerTypeName: String,
        propertyName: String,
        propertyFieldNumber: UInt32,
        relatedTypeName: String,
        cardinality: RelationshipCardinality,
        deleteRule: DeleteRule
    ) {
        self.ownerTypeName = ownerTypeName
        self.propertyName = propertyName
        self.propertyFieldNumber = propertyFieldNumber
        self.relatedTypeName = relatedTypeName
        self.cardinality = cardinality
        self.deleteRule = deleteRule
    }
}

extension RelationshipDescriptor: CustomStringConvertible {
    public var description: String {
        "RelationshipDescriptor(\(name) -> \(relatedTypeName), \(cardinality), \(deleteRule))"
    }
}

extension Persistable {
    public static var relationshipDescriptors: [RelationshipDescriptor] {
        get throws(IndexDeclarationError) {
            try descriptors.compactMap { $0 as? RelationshipDescriptor }
        }
    }
}
