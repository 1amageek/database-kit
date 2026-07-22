/// A typed marker used by `#Directory` to select a dynamic partition field.
///
/// The macro compiles this key path into a `DirectoryPathComponent.dynamicField`
/// containing the canonical persisted field name.
public struct Field<Root> {
    public let value: PartialKeyPath<Root>

    public init(_ keyPath: PartialKeyPath<Root>) {
        self.value = keyPath
    }
}
