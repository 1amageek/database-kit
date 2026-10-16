import DatabaseKit
import Testing

@Suite("SPARQL pattern export")
struct SPARQLPatternExportTests {
    @Test("Static LIKE export preserves case, metacharacters, and disabled escape")
    func staticLikeExport() throws {
        for (pattern, translated) in [("A%_", "^A.*.$"), ("a.[b]", "^a\\.\\[b\\]$"),
                                      ("a\\b\"", "^a\\\\b\"$")] {
            let expression = Expression.patternMatch(
                subject: .variable(Variable("value")), pattern: .string(pattern),
                escape: nil, kind: .like
            )
            let expected = "REGEX(?value, \(try Literal.string(translated).toSPARQL()))"
            #expect(try expression.toSPARQL() == expected)
        }
    }

    @Test("SQL pattern extensions require an explicit Graph contract")
    func unsupportedPatterns() {
        let expressions: [Expression] = [
            .patternMatch(subject: .string("a"), pattern: .col("pattern"), escape: nil, kind: .like),
            .patternMatch(subject: .string("a"), pattern: .string("a"), escape: .string(""), kind: .like),
            .patternMatch(subject: .string("a"), pattern: .string("a"), escape: nil, kind: .caseInsensitiveLike),
            .patternMatch(subject: .string("a"), pattern: .string("a"), escape: nil, kind: .similarTo),
            .patternMatch(subject: .string("a"), pattern: .string("a"), escape: nil, kind: .regularExpression),
            .patternMatch(subject: .string("a"), pattern: .string("a"), escape: nil, kind: .caseInsensitiveRegularExpression),
        ]
        for expression in expressions {
            #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) {
                try expression.toSPARQL()
            }
        }
    }
}
