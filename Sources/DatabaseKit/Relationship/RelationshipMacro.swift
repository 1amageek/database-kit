/// Marks a stored `PersistableReference<Target>` field as a maintained relationship.
///
/// Supported field shapes are:
/// - `PersistableReference<Target>`
/// - `PersistableReference<Target>?`
/// - `[PersistableReference<Target>]`
///
/// The target type, partition binding, and identifier components are carried by
/// the reference value. The attribute only defines deletion behavior.
@attached(peer)
public macro Relationship(
    deleteRule: DeleteRule = .nullify
) = #externalMacro(module: "DatabaseKitMacros", type: "RelationshipMacro")
