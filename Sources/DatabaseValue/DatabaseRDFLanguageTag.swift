/// A well-formed BCP 47 language tag with canonical ASCII-lowercase storage.
public struct DatabaseRDFLanguageTag: Sendable, Hashable, Comparable,
    CustomStringConvertible
{
    public let rawValue: String

    public init(_ rawValue: String) throws(DatabaseRDFLanguageTagError) {
        guard !rawValue.isEmpty else { throw .empty }
        guard DatabaseRDFLanguageTagParser.validate(rawValue) else {
            throw .invalidSyntax
        }
        self.rawValue = DatabaseStringIdentity.canonicalASCIILowercase(rawValue)
    }

    init(validatedRawValue rawValue: String) {
        self.rawValue = rawValue
    }

    public static let english = Self(validatedRawValue: "en")

    public static func == (lhs: Self, rhs: Self) -> Bool {
        DatabaseStringIdentity.equal(lhs.rawValue, rhs.rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        DatabaseStringIdentity.less(lhs.rawValue, rhs.rawValue)
    }

    public func hash(into hasher: inout Hasher) {
        DatabaseStringIdentity.hash(rawValue, into: &hasher)
    }

    public var description: String { rawValue }
}
