/// A context-free typed input that lowers to the canonical Fusion model.
public protocol FusionQueryInput<Item>: Sendable {
    associatedtype Item: Persistable

    var fusionInput: FusionInput { get }
}
