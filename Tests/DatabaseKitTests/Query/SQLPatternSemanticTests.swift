import DatabaseKit
import Testing

@Suite("SQL pattern declaration semantics")
struct SQLPatternSemanticTests {
    private var kinds: [PatternMatchKind] { [.like, .caseInsensitiveLike, .similarTo, .regularExpression, .caseInsensitiveRegularExpression] }

    @Test("Pattern kind and absent versus NULL escape preserve exact identity and hashing")
    func exactPatternIdentity() {
        let values = kinds.map { Expression.patternMatch(subject: .col("s"), pattern: .col("p"), escape: nil, kind: $0) }
        #expect(Set(values).count == 5)
        let disabled = values[0]
        let nullEscape = Expression.patternMatch(subject: .col("s"), pattern: .col("p"), escape: .null, kind: .like)
        #expect(disabled != nullEscape)
        #expect(Set([disabled, nullEscape]).count == 2)
        func nested(_ leaf: Expression) -> Expression {
            var expression = leaf
            for _ in 0..<48 {
                expression = .patternMatch(subject: expression, pattern: .col("p"), escape: .col("e"), kind: .like)
            }
            return .concatenate(expression, .string("tail"))
        }
        #expect(nested(.col("same")) == nested(.col("same")))
        #expect(nested(.col("same")) != nested(.col("different")))
        #expect(Set([nested(.col("same")), nested(.col("same"))]).count == 1)
    }

    @Test("Parameters bind subject pattern escape and concatenation without lost child edges")
    func parameterChildren() throws {
        let expression = Expression.patternMatch(subject: .parameter(.position(1)),
            pattern: .concatenate(.parameter(.position(2)), .string("%")),
            escape: .parameter(.position(3)), kind: .like)
        let query = SelectQuery(projection: .items([ProjectionItem(expression)]), source: .values([], columnNames: nil))
        let binder = try QueryParameterBinder(parameters: [
            QueryParameter(position: 1, value: .primitive(.string("value")), type: .sql(.text)),
            QueryParameter(position: 2, value: .primitive(.string("v")), type: .sql(.text)),
            QueryParameter(position: 3, value: .primitive(.null), type: .sql(.text)),
        ])
        try binder.validate(.select(query))
        let bound = try binder.bind(.select(query))
        guard case .select(let selected) = bound, case .items(let items) = selected.projection,
              case .patternMatch(let subject, let pattern, let escape, let kind) = items[0].expression else {
            Issue.record("Pattern binding changed its semantic form"); return
        }
        #expect(subject == .literal(.queryValue(.primitive(.string("value")), type: .sql(.text))))
        #expect(pattern == .concatenate(.literal(.queryValue(.primitive(.string("v")), type: .sql(.text))), .string("%")))
        #expect(escape == .literal(.queryValue(.primitive(.null), type: .sql(.text))))
        #expect(kind == .like)
        #expect(throws: QueryParameterBindingError.missingPosition(3)) {
            try QueryParameterBinder(parameters: [
                QueryParameter(position: 1, value: .primitive(.null)), QueryParameter(position: 2, value: .primitive(.null)),
            ]).validate(.select(query))
        }
    }

    @Test("Reference collection reaches all pattern expressions and concatenation operands")
    func referencedChildren() {
        let expression = Expression.patternMatch(subject: .concatenate(.col("subject"), .variable(Variable("s"))),
            pattern: .concatenate(.col("pattern"), .variable(Variable("p"))),
            escape: .concatenate(.col("escape"), .variable(Variable("e"))), kind: .like)
        let query = SelectQuery(projection: .items([]), source: .values([], columnNames: nil), filter: expression)
        #expect(query.referencedColumns == Set([ColumnRef("subject"), ColumnRef("pattern"), ColumnRef("escape")]))
        #expect(query.referencedVariables == Set(["s", "p", "e"]))
    }

    @Test("ERE escape structure and each dynamic child obey structural admission")
    func structuralAdmission() throws {
        for kind in kinds {
            let expression = Expression.patternMatch(subject: .null, pattern: .null, escape: nil, kind: kind)
            try QueryStructuralValidator.validate(expression, limits: .default)
            let withEscape = Expression.patternMatch(subject: .null, pattern: .null, escape: .null, kind: kind)
            if kind.permitsEscape { try QueryStructuralValidator.validate(withEscape, limits: .default) }
            else {
                #expect(throws: QueryStructuralValidationError.invalidPatternEscape) {
                    try QueryStructuralValidator.validate(withEscape, limits: .default)
                }
            }
        }
        let expression = Expression.patternMatch(subject: .parameter(.position(1)), pattern: .parameter(.position(2)),
            escape: .parameter(.position(3)), kind: .like)
        try QueryStructuralValidator.validate(expression, limits: QueryStructuralLimits(maximumTotalNodes: 4))
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(expression, limits: QueryStructuralLimits(maximumTotalNodes: 3))
        }
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(.patternMatch(subject: .null, pattern: .string(String(repeating: "x", count: 1000)),
                escape: nil, kind: .like), limits: QueryStructuralLimits(maximumRetainedBytes: 100))
        }
        let bytes = UInt64("é".utf8.count)
        let children: [Expression] = [
            .patternMatch(subject: .string("é"), pattern: .null, escape: nil, kind: .like),
            .patternMatch(subject: .null, pattern: .string("é"), escape: nil, kind: .like),
            .patternMatch(subject: .null, pattern: .null, escape: .string("é"), kind: .like),
            .concatenate(.string("é"), .null),
        ]
        for child in children {
            try QueryStructuralValidator.validate(child, limits: QueryStructuralLimits(maximumRetainedBytes: bytes))
            #expect(throws: QueryStructuralValidationError.self) {
                try QueryStructuralValidator.validate(child, limits: QueryStructuralLimits(maximumRetainedBytes: bytes - 1))
            }
        }
    }
}
