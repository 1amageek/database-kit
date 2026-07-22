/// Marks a stored `DatabaseReference<Target>` field as a maintained relationship.
///
/// Supported field shapes are:
/// - `DatabaseReference<Target>`
/// - `DatabaseReference<Target>?`
/// - `[DatabaseReference<Target>]`
///
/// The target type, partition binding, and identifier components are carried by
/// the reference value. The attribute only defines deletion behavior.
@attached(peer)
public macro Relationship(
    deleteRule: DeleteRule = .nullify
) = #externalMacro(module: "RelationshipMacros", type: "RelationshipMacro")
