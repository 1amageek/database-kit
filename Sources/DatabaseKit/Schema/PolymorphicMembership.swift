/// Static membership of one entity in a polymorphic schema group.
///
/// The group declaration is inherited through `Polymorphable`; the concrete
/// entity name and field numbers are resolved when `Schema` is constructed.
public struct PolymorphicMembership: Sendable, Hashable {
    public let identifier: String
    public let directoryComponents: [DirectoryPathComponent]
    public let directoryLayer: DirectoryLayer
    public let indexes: [PolymorphicIndexDefinition]

    public init(
        identifier: String,
        directoryComponents: [DirectoryPathComponent],
        directoryLayer: DirectoryLayer,
        indexes: [PolymorphicIndexDefinition]
    ) {
        self.identifier = identifier
        self.directoryComponents = directoryComponents
        self.directoryLayer = directoryLayer
        self.indexes = indexes
    }
}
