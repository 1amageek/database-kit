import DatabaseTypes

/// Wire-safe metadata for a protocol-oriented polymorphic source.
///
/// A polymorphic group is identified by the `@Polymorphable` protocol identifier
/// and describes the shared directory and shared indexes that span all conforming
/// concrete `Persistable` types.
public struct PolymorphicGroup: Sendable, Codable, Equatable, Hashable {
    public let identifier: String
    public let directoryComponents: [DirectoryPathComponent]
    public let directoryLayer: DirectoryLayer
    public let indexes: [IndexDescriptorMetadata]
    public let memberTypeNames: [String]

    public init(
        identifier: String,
        directoryComponents: [DirectoryPathComponent],
        directoryLayer: DirectoryLayer = .default,
        indexes: [IndexDescriptorMetadata] = [],
        memberTypeNames: [String] = []
    ) {
        self.identifier = identifier
        self.directoryComponents = directoryComponents
        self.directoryLayer = directoryLayer
        self.indexes = indexes
        self.memberTypeNames = memberTypeNames.sorted()
    }

    public func resolvedDirectoryPath() throws -> [String] {
        try directoryComponents.map { component in
            switch component {
            case .staticPath(let value):
                return value
            case .dynamicField(let fieldName):
                throw DirectoryPathError.missingFields([fieldName])
            }
        }
    }

    static func extractDirectoryComponents(
        from components: [DirectoryPathComponent]
    ) -> [DirectoryPathComponent] {
        components
    }
}
