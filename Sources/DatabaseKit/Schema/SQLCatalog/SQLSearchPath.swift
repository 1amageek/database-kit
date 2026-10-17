/// An ordered immutable search path, preserving explicit empty and repeated entries.
public struct SQLSearchPath: Sendable, Hashable {
    public let entries: [SQLSearchPathEntry]

    public init(entries: [SQLSearchPathEntry]) throws(SQLCatalogError) {
        for entry in entries {
            if case .schema(let name) = entry {
                try SQLIdentifier.validate(name)
            }
        }
        self.entries = entries
    }

    /// Search the authenticated principal's namespace, then the public namespace.
    public static var `default`: Self {
        Self(validatedEntries: [.currentUser, .schema("public")])
    }

    private init(validatedEntries: [SQLSearchPathEntry]) {
        self.entries = validatedEntries
    }
}
