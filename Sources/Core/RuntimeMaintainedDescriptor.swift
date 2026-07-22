/// Metadata whose storage invariants require a container-scoped runtime maintainer.
public protocol RuntimeMaintainedDescriptor: Descriptor {
    /// Stable identifier of the maintainer required to preserve this descriptor.
    var runtimeMaintainerIdentifier: String { get }
}
