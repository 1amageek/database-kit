import Foundation

/// Wire-safe metadata for a protocol-oriented polymorphic source.
///
/// A polymorphic group is identified by the `@Polymorphable` protocol identifier
/// and describes the shared directory and shared indexes that span all conforming
/// concrete `Persistable` types.
public struct PolymorphicGroup: Sendable, Codable, Equatable, Hashable {
    public let identifier: String
    public let directoryComponents: [DirectoryComponentCatalog]
    public let directoryLayer: DirectoryLayer
    public let indexes: [AnyIndexDescriptor]
    public let memberTypeNames: [String]

    public init(
        identifier: String,
        directoryComponents: [DirectoryComponentCatalog],
        directoryLayer: DirectoryLayer = .default,
        indexes: [AnyIndexDescriptor] = [],
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
        from components: [any DirectoryPathElement]
    ) -> [DirectoryComponentCatalog] {
        components.map { component in
            if let path = component as? Path {
                return .staticPath(path.value)
            }
            if let value = component as? String {
                return .staticPath(value)
            }
            return .staticPath("_unknown")
        }
    }
}
