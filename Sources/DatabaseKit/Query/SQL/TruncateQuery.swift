/// A relation-set truncation with explicit identity and reference policy.
public struct TruncateQuery: Sendable, Equatable, Hashable {
    public let tables: [TableRef]
    public let identity: SQLTruncateIdentity
    public let references: SQLTruncateReferences

    public init(tables: [TableRef], identity: SQLTruncateIdentity = .continue,
                references: SQLTruncateReferences = .restrict) {
        self.tables = tables
        self.identity = identity
        self.references = references
    }
}
