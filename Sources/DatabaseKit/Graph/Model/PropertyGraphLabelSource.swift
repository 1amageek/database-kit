/// Source of the edge label in a property-graph index declaration.
public enum PropertyGraphLabelSource: Sendable, Hashable {
    /// Every persisted edge supplies its label from a selected model field.
    case field

    /// The schema supplies one implicit label for every indexed edge.
    case implicit
}
