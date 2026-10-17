/// One intrinsically valid constraint; data enforcement is runtime-owned.
public struct SQLConstraint: Sendable, Hashable {
    public let attributes: SQLConstraintAttributes
    public let kind: SQLConstraintKind
    public var id: String { attributes.id }
    public var name: String { attributes.name }
    public var timing: SQLConstraintTiming { attributes.timing }

    public init(attributes: SQLConstraintAttributes, kind: SQLConstraintKind) throws(SQLCatalogError) {
        switch kind {
        case .unique(let ids, _): try SQLIdentifier.validateColumnIDs(ids)
        case .notNull(let id):
            try SQLIdentifier.validate(id)
            guard attributes.timing == .immediate else { throw .invalidConstraintTiming(attributes.id) }
        case .check:
            guard attributes.timing == .immediate else { throw .invalidConstraintTiming(attributes.id) }
        case .foreignKey: break
        }
        self.attributes = attributes
        self.kind = kind
    }
}
