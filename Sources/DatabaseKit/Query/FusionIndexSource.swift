import DatabaseTypes

/// A context-free physical index request in a Fusion plan.
public struct FusionIndexSource: Sendable, Equatable, Hashable {
    public let selection: FusionIndexSelection
    /// Logical model fields whose values the feature interprets. This is
    /// semantic authority, distinct from fields used to select a physical
    /// index, and must be authorized before feature validation.
    public let referencedFields: [FieldIdentity]
    public let parameters: [String: FieldValue]

    public init(
        selection: FusionIndexSelection,
        referencedFields: [FieldIdentity] = [],
        parameters: [String: FieldValue] = [:]
    ) {
        self.selection = selection
        self.referencedFields = referencedFields
        self.parameters = parameters
    }
}
