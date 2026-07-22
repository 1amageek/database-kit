public enum DatabaseRDFLiteralAnnotation: Sendable, Hashable, Comparable {
    case typed(DatabaseRDFTypedLiteralDatatype)
    case languageTagged(DatabaseRDFLanguageTag)
    case directionalLanguageTagged(
        DatabaseRDFLanguageTag,
        DatabaseRDFDirection
    )

    public var datatype: DatabaseRDFIRI {
        switch self {
        case .typed(let datatype):
            return datatype.iri
        case .languageTagged:
            return .rdfLanguageString
        case .directionalLanguageTagged:
            return .rdfDirectionalLanguageString
        }
    }

    public var language: DatabaseRDFLanguageTag? {
        switch self {
        case .typed:
            return nil
        case .languageTagged(let language),
             .directionalLanguageTagged(let language, _):
            return language
        }
    }

    public var direction: DatabaseRDFDirection? {
        switch self {
        case .typed, .languageTagged:
            return nil
        case .directionalLanguageTagged(_, let direction):
            return direction
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.typed(let left), .typed(let right)):
            return left < right
        case (.languageTagged(let left), .languageTagged(let right)):
            return left < right
        case (
            .directionalLanguageTagged(let leftLanguage, let leftDirection),
            .directionalLanguageTagged(let rightLanguage, let rightDirection)
        ):
            if leftLanguage != rightLanguage {
                return leftLanguage < rightLanguage
            }
            return leftDirection < rightDirection
        default:
            return rank(lhs) < rank(rhs)
        }
    }

    private static func rank(_ annotation: Self) -> UInt8 {
        switch annotation {
        case .typed: return 0
        case .languageTagged: return 1
        case .directionalLanguageTagged: return 2
        }
    }
}
