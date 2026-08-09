import DatabaseTypes

/// A backend-defined read point whose ordering is meaningful only inside one
/// storage domain.
public struct DomainReadPoint: Sendable, Hashable {
    public enum Position: Sendable, Hashable {
        case version(UInt64)
        case opaque(ByteString)
    }

    public let domainID: String
    public let position: Position

    public init(
        domainID: String,
        position: Position
    ) throws(BaseIdentifierError) {
        _ = try Base.ID(domainID)
        self.domainID = domainID
        self.position = position
    }
}
