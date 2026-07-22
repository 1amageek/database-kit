public indirect enum DatabaseSHACLPath: Sendable, Hashable {
    case predicate(String)
    case inverse(DatabaseSHACLPath)
    case sequence([DatabaseSHACLPath])
    case alternative([DatabaseSHACLPath])
    case zeroOrMore(DatabaseSHACLPath)
    case oneOrMore(DatabaseSHACLPath)
    case zeroOrOne(DatabaseSHACLPath)
}
