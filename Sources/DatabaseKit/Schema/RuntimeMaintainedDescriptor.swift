import DatabaseTypes
/// Metadata whose storage invariants require a schema-generation runtime maintainer.
public protocol RuntimeMaintainedDescriptor: Descriptor {
    /// Stable identifier of the maintainer required to preserve this descriptor.
    var runtimeMaintainerIdentifier: String { get }
}
