/// Static metadata that defines one polymorphic persistence group.
///
/// The attached `@Polymorphable` macro emits one concrete declaration for each
/// annotated protocol. Concrete models inherit that declaration through the
/// protocol's `Polymorphable.Group` associated type.
public protocol PolymorphicGroupDeclaration: Sendable {
    /// Stable identifier shared by every concrete model in the group.
    static var identifier: String { get }

    /// Shared storage directory used for polymorphic reads and writes.
    static var directoryComponents: [DirectoryPathComponent] { get }

    /// Directory policy applied to the shared storage directory.
    static var directoryLayer: DirectoryLayer { get }

    /// Logical indexes shared by every concrete model in the group.
    static var indexes: [PolymorphicIndexDefinition] { get }
}
