import DatabaseTypes

/// An authenticated identity available to authorization policies.
///
/// Authentication adapters construct this value only after validating their
/// external credential. DatabaseKit does not authenticate credentials.
public struct Principal: Sendable, Hashable {
    public let identifier: String
    public let roles: Set<String>
    public let claims: FieldObject

    public init(
        identifier: String,
        roles: Set<String> = [],
        claims: FieldObject = FieldObject()
    ) {
        self.identifier = identifier
        self.roles = roles
        self.claims = claims
    }
}
