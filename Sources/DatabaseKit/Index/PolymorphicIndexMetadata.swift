import DatabaseTypes

/// Concrete-number-independent metadata for an index shared by a polymorphic group.
public struct PolymorphicIndexMetadata: Sendable, Hashable {
    public let name: String
    public let kindIdentifier: String
    public let subspaceStructure: SubspaceStructure
    public let fields: [PolymorphicIndexField]
    public let metadata: [String: FieldValue]
    public let commonOptions: CommonIndexOptions
    public let storedFieldNames: [String]

    public var fieldNames: [String] {
        fields.map { $0.name }
    }

    package init(
        descriptor: IndexDescriptor,
        fields: [PolymorphicIndexField]
    ) {
        self.name = descriptor.name
        self.kindIdentifier = descriptor.kind.identifier
        self.subspaceStructure = descriptor.kind.subspaceStructure
        self.fields = fields
        self.metadata = descriptor.kind.metadata
        self.commonOptions = descriptor.commonOptions
        self.storedFieldNames = descriptor.storedFieldNames
    }
}
