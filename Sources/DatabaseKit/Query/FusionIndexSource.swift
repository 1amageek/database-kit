import DatabaseTypes

/// A context-free physical index request in a Fusion plan.
public struct FusionIndexSource: Sendable, Equatable, Hashable {
    public let selection: FusionIndexSelection
    public let parameters: [String: FieldValue]

    public init(
        selection: FusionIndexSelection,
        parameters: [String: FieldValue] = [:]
    ) {
        self.selection = selection
        self.parameters = parameters
    }
}
