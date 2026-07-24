import DatabaseTypes
import DatabaseKit
import Testing

@Suite("SPARQL semantic validation")
struct SPARQLSemanticValidatorTests {
    @Test("One blank node label can be reused inside one basic graph pattern")
    func labelWithinOneBasicGraphPatternIsValid() throws {
        let query = SelectQuery(
            projection: .all,
            source: .graphPattern(
                .basic([
                    TriplePattern(
                        subject: .blankNode("shared"),
                        predicate: .iri("urn:predicate"),
                        object: .blankNode("shared")
                    )
                ])
            )
        )

        try SPARQLSemanticValidator.validate(query)
    }

    @Test("One blank node label cannot cross basic graph patterns")
    func labelAcrossBasicGraphPatternsIsInvalid() {
        let query = SelectQuery(
            projection: .all,
            source: .graphPattern(
                .join(
                    .basic([triple(subject: .blankNode("shared"))]),
                    .basic([triple(subject: .blankNode("shared"))])
                )
            )
        )

        #expect(
            throws: SPARQLSemanticValidationError
                .labelCrossesBasicGraphPatterns("shared")
        ) {
            try SPARQLSemanticValidator.validate(query)
        }
    }

    @Test("Nested RDF-star terms participate in basic graph pattern scope")
    func nestedTermLabelsAreValidated() {
        let nested = SPARQLTerm.tripleTerm(
            subject: .blankNode("nested"),
            predicate: .iri("urn:nested-predicate"),
            object: .literal(.string("value"))
        )
        let query = SelectQuery(
            projection: .all,
            source: .graphPattern(
                .join(
                    .basic([triple(subject: nested)]),
                    .basic([triple(subject: .blankNode("nested"))])
                )
            )
        )

        #expect(
            throws: SPARQLSemanticValidationError
                .labelCrossesBasicGraphPatterns("nested")
        ) {
            try SPARQLSemanticValidator.validate(query)
        }
    }

    @Test("One blank node label can be reused inside one INSERT DATA operation")
    func labelWithinOneInsertDataOperationIsValid() throws {
        let request = SPARQLUpdateRequest(
            firstOperation: .insertData(
                InsertDataQuery(
                    quads: [
                        quad(subject: .blankNode("shared")),
                        quad(subject: .blankNode("shared"), object: .iri("urn:second")),
                    ]
                )
            )
        )

        try SPARQLSemanticValidator.validate(request)
    }

    @Test("One blank node label cannot cross INSERT DATA operations")
    func labelAcrossInsertDataOperationsIsInvalid() {
        let request = SPARQLUpdateRequest(
            firstOperation: .insertData(
                InsertDataQuery(quads: [quad(subject: .blankNode("shared"))])
            ),
            additionalOperations: [
                .insertData(
                    InsertDataQuery(quads: [quad(subject: .blankNode("shared"))])
                )
            ]
        )

        #expect(
            throws: SPARQLSemanticValidationError
                .labelCrossesInsertDataOperations("shared")
        ) {
            try SPARQLSemanticValidator.validate(request)
        }
    }

    @Test("One blank node label cannot cross WHERE clauses")
    func labelAcrossWhereClausesIsInvalid() {
        let request = SPARQLUpdateRequest(
            firstOperation: modify(whereSubject: .blankNode("shared")),
            additionalOperations: [modify(whereSubject: .blankNode("shared"))]
        )

        #expect(
            throws: SPARQLSemanticValidationError
                .labelCrossesWhereClauses("shared")
        ) {
            try SPARQLSemanticValidator.validate(request)
        }
    }

    @Test("Blank node labels may be reused in different modify templates")
    func labelAcrossModifyTemplatesIsValid() throws {
        let first = SPARQLUpdateOperation.modify(
            SPARQLModifyOperation(
                action: .insert([quad(subject: .blankNode("shared"))]),
                wherePattern: .basic([triple(subject: .variable("subject"))])
            )
        )
        let second = SPARQLUpdateOperation.modify(
            SPARQLModifyOperation(
                action: .insert([quad(subject: .blankNode("shared"))]),
                wherePattern: .basic([triple(subject: .variable("other"))])
            )
        )
        let request = SPARQLUpdateRequest(
            firstOperation: first,
            additionalOperations: [second]
        )

        try SPARQLSemanticValidator.validate(request)
    }

    @Test("Nested EXISTS queries share the request-level query scope")
    func nestedExistsSharesQueryScope() {
        let existsQuery = SelectQuery(
            projection: .all,
            source: .graphPattern(
                .basic([triple(subject: .blankNode("shared"))])
            )
        )
        let query = SelectQuery(
            projection: .all,
            source: .graphPattern(
                .filter(
                    .basic([triple(subject: .blankNode("shared"))]),
                    .exists(existsQuery)
                )
            )
        )

        #expect(
            throws: SPARQLSemanticValidationError
                .labelCrossesBasicGraphPatterns("shared")
        ) {
            try SPARQLSemanticValidator.validate(query)
        }
    }

    @Test(
        "RDF nodes embedded in Literal cannot bypass canonical SPARQLTerm cases",
        arguments: [
            Literal.blankNode("hidden"),
            Literal.rdfTerm(
                .blankNode(fixtureBlankNode("hidden"))
            ),
            Literal.iri("urn:hidden"),
            Literal.rdfTerm(.iri(fixtureIRI("urn:hidden"))),
        ]
    )
    func rdfNodesEmbeddedInLiteralAreInvalid(_ literal: Literal) {
        let query = query(object: .literal(literal))

        #expect(throws: SPARQLSemanticValidationError.nonCanonicalTermLiteral) {
            try SPARQLSemanticValidator.validate(query)
        }
    }

    @Test("Canonical RDF literals embedded in Literal remain valid")
    func canonicalRDFLiteralIsValid() throws {
        let literal = RDFLiteral(
            lexicalForm: "value",
            datatype: .xsdString
        )

        try SPARQLSemanticValidator.validate(
            query(object: .literal(.rdfTerm(.literal(literal))))
        )
    }

    @Test(
        "Blank node constants cannot occur in expressions",
        arguments: [
            Literal.blankNode("hidden"),
            Literal.rdfTerm(
                .blankNode(fixtureBlankNode("hidden"))
            ),
        ]
    )
    func blankNodeExpressionIsInvalid(_ literal: Literal) {
        let query = SelectQuery(
            projection: .items([ProjectionItem(.literal(literal))]),
            source: .graphPattern(.basic([]))
        )

        #expect(
            throws: SPARQLSemanticValidationError.blankNodeNotAllowed(
                context: .expression,
                label: "hidden"
            )
        ) {
            try SPARQLSemanticValidator.validate(query)
        }
    }

    @Test(
        "Blank node constants cannot occur in VALUES",
        arguments: [
            Literal.blankNode("hidden"),
            Literal.rdfTerm(
                .blankNode(fixtureBlankNode("hidden"))
            ),
        ]
    )
    func blankNodeValueIsInvalid(_ literal: Literal) {
        let query = SelectQuery(
            projection: .all,
            source: .graphPattern(
                .values(variables: ["value"], bindings: [[literal]])
            )
        )

        #expect(
            throws: SPARQLSemanticValidationError.blankNodeNotAllowed(
                context: .values,
                label: "hidden"
            )
        ) {
            try SPARQLSemanticValidator.validate(query)
        }
    }

    @Test("Encoded QueryIR cannot forge an execution-only variable")
    func reservedVariableNameIsInvalid() {
        let reserved = "visible\u{0}database-framework:blank:0:forged"
        let query = SelectQuery(
            projection: .all,
            source: .graphPattern(
                .basic([triple(subject: .variable(reserved))])
            )
        )

        #expect(
            throws: SPARQLSemanticValidationError.invalidVariableName(
                reserved,
                .invalidContinuationScalar(0)
            )
        ) {
            try SPARQLSemanticValidator.validate(query)
        }
    }

    @Test("Projection aliases cannot forge an execution-only variable")
    func reservedProjectionAliasIsInvalid() {
        let reserved = "alias\u{0}database-framework:forged"
        let query = SelectQuery(
            projection: .items([
                ProjectionItem(.variable(Variable("value")), alias: reserved)
            ]),
            source: .graphPattern(.basic([]))
        )

        #expect(
            throws: SPARQLSemanticValidationError.invalidVariableName(
                reserved,
                .invalidContinuationScalar(0)
            )
        ) {
            try SPARQLSemanticValidator.validate(query)
        }
    }

    @Test("BIND targets cannot forge an execution-only variable")
    func reservedBindTargetIsInvalid() {
        let reserved = "bind\u{0}database-framework:forged"
        let query = SelectQuery(
            projection: .all,
            source: .graphPattern(
                .bind(
                    .basic([]),
                    variable: reserved,
                    expression: .literal(.string("value"))
                )
            )
        )

        #expect(
            throws: SPARQLSemanticValidationError.invalidVariableName(
                reserved,
                .invalidContinuationScalar(0)
            )
        ) {
            try SPARQLSemanticValidator.validate(query)
        }
    }

    @Test(
        "Canonical variables reject sigils, empty names, and invalid scalars",
        arguments: [
            ("", SPARQLVariableNameError.empty),
            ("?value", .leadingSigil(0x3F)),
            ("$value", .leadingSigil(0x24)),
            ("value-with-hyphen", .invalidContinuationScalar(0x2D)),
            (" value", .invalidStartScalar(0x20)),
        ]
    )
    func invalidCanonicalVariableNames(
        _ name: String,
        _ reason: SPARQLVariableNameError
    ) {
        let pattern = GraphPattern.basic([
            triple(subject: .variable(name))
        ])

        #expect(
            throws: SPARQLSemanticValidationError.invalidVariableName(
                name,
                reason
            )
        ) {
            try SPARQLSemanticValidator.validate(pattern)
        }
    }

    @Test(
        "Predicate positions accept only variables and IRI forms",
        arguments: [
            SPARQLTerm.literal(.string("predicate")),
            SPARQLTerm.blankNode("predicate"),
            SPARQLTerm.tripleTerm(
                subject: .iri("urn:subject"),
                predicate: .iri("urn:predicate"),
                object: .iri("urn:object")
            ),
        ]
    )
    func invalidPredicateTermIsRejected(_ predicate: SPARQLTerm) {
        let query = SelectQuery(
            projection: .all,
            source: .graphPattern(
                .basic([
                    TriplePattern(
                        subject: .variable("subject"),
                        predicate: predicate,
                        object: .variable("object")
                    )
                ])
            )
        )

        #expect(throws: SPARQLSemanticValidationError.self) {
            try SPARQLSemanticValidator.validate(query)
        }
    }

    @Test("DELETE DATA rejects blank nodes before execution")
    func deleteDataBlankNodeIsInvalid() {
        let request = SPARQLUpdateRequest(
            firstOperation: .deleteData(
                DeleteDataQuery(quads: [quad(subject: .blankNode("deleted"))])
            )
        )

        #expect(
            throws: SPARQLSemanticValidationError.blankNodeNotAllowed(
                context: .deleteData,
                label: "deleted"
            )
        ) {
            try SPARQLSemanticValidator.validate(request)
        }
    }

    @Test("DELETE WHERE rejects blank nodes before execution")
    func deleteWhereBlankNodeIsInvalid() {
        let request = SPARQLUpdateRequest(
            firstOperation: .deleteWhere(
                DeleteWhereQuery(pattern: [quad(subject: .blankNode("deleted"))])
            )
        )

        #expect(
            throws: SPARQLSemanticValidationError.blankNodeNotAllowed(
                context: .deleteWhere,
                label: "deleted"
            )
        ) {
            try SPARQLSemanticValidator.validate(request)
        }
    }

    @Test("Modify DELETE templates reject blank nodes before WHERE evaluation")
    func modifyDeleteTemplateBlankNodeIsInvalid() {
        let request = SPARQLUpdateRequest(
            firstOperation: .modify(
                SPARQLModifyOperation(
                    action: .delete([quad(subject: .blankNode("deleted"))]),
                    wherePattern: .basic([])
                )
            )
        )

        #expect(
            throws: SPARQLSemanticValidationError.blankNodeNotAllowed(
                context: .deleteTemplate,
                label: "deleted"
            )
        ) {
            try SPARQLSemanticValidator.validate(request)
        }
    }

    @Test("Modify DELETE/INSERT validates its DELETE template first")
    func modifyDeleteAndInsertTemplateBlankNodeIsInvalid() {
        let request = SPARQLUpdateRequest(
            firstOperation: .modify(
                SPARQLModifyOperation(
                    action: .deleteAndInsert(
                        delete: [quad(subject: .blankNode("deleted"))],
                        insert: [quad(subject: .blankNode("inserted"))]
                    ),
                    wherePattern: .basic([])
                )
            )
        )

        #expect(
            throws: SPARQLSemanticValidationError.blankNodeNotAllowed(
                context: .deleteTemplate,
                label: "deleted"
            )
        ) {
            try SPARQLSemanticValidator.validate(request)
        }
    }

    @Test("Ground data operations reject variables")
    func groundDataVariableIsInvalid() {
        let operations: [SPARQLUpdateOperation] = [
            .insertData(
                InsertDataQuery(quads: [quad(subject: .variable("subject"))])
            ),
            .deleteData(
                DeleteDataQuery(quads: [quad(subject: .variable("subject"))])
            ),
        ]

        for operation in operations {
            let request = SPARQLUpdateRequest(firstOperation: operation)
            #expect(throws: SPARQLSemanticValidationError.self) {
                try SPARQLSemanticValidator.validate(request)
            }
        }
    }

    @Test("DESCRIBE resources reject blank nodes")
    func describeBlankNodeResourceIsInvalid() {
        let statement = QueryStatement.describe(
            DescribeQuery(selection: .resources(first: .blankNode("resource"), additional: []))
        )

        #expect(
            throws: SPARQLSemanticValidationError.invalidTermRole(
                role: .describeResource,
                kind: .blankNode
            )
        ) {
            try SPARQLSemanticValidator.validate(statement)
        }
    }

    @Test("Unbound expression variables remain runtime semantics")
    func unboundExpressionVariablesAreValid() throws {
        let query = SelectQuery(
            projection: .items([
                ProjectionItem(.variable(Variable("missing")))
            ]),
            source: .graphPattern(
                .filter(
                    .basic([]),
                    .equal(
                        .variable(Variable("alsoMissing")),
                        .literal(.int(1))
                    )
                )
            )
        )

        try SPARQLSemanticValidator.validate(query)
    }

    @Test(
        "Aggregates are rejected in FILTER, BIND, and GROUP BY",
        arguments: [
            SPARQLSemanticValidationError.AggregateContext.filter,
            .bind,
            .groupBy,
        ]
    )
    func aggregatePlacementIsValidated(
        _ context: SPARQLSemanticValidationError.AggregateContext
    ) {
        let aggregate = Expression.aggregate(
            .sum(.variable(Variable("value")), distinct: false)
        )
        let source: DataSource
        let groupBy: [Expression]?
        switch context {
        case .filter:
            source = .graphPattern(.filter(.basic([]), aggregate))
            groupBy = nil
        case .bind:
            source = .graphPattern(
                .bind(.basic([]), variable: "sum", expression: aggregate)
            )
            groupBy = nil
        case .groupBy:
            source = .graphPattern(.basic([]))
            groupBy = [aggregate]
        case .aggregateOperand:
            Issue.record("Aggregate operand is covered by the nested test")
            return
        }
        let query = SelectQuery(
            projection: .items([
                ProjectionItem(.literal(.int(1)), alias: "result")
            ]),
            source: source,
            groupBy: groupBy
        )

        #expect(
            throws: SPARQLSemanticValidationError
                .aggregateNotAllowed(context)
        ) {
            try SPARQLSemanticValidator.validate(query)
        }
    }

    @Test("Aggregate operands cannot contain aggregates")
    func nestedAggregateIsInvalid() {
        let inner = Expression.aggregate(
            .count(.variable(Variable("value")), distinct: false)
        )
        let outer = Expression.aggregate(.sum(inner, distinct: false))
        let query = SelectQuery(
            projection: .items([ProjectionItem(outer, alias: "sum")]),
            source: .graphPattern(.basic([]))
        )

        #expect(throws: SPARQLSemanticValidationError.nestedAggregate) {
            try SPARQLSemanticValidator.validate(query)
        }
    }

    @Test("Wildcard projection uses the grouped visible variable set")
    func groupedWildcardIsValid() throws {
        let queries = [
            SelectQuery(
                projection: .all,
                source: .graphPattern(.basic([])),
                groupBy: [.variable(Variable("key"))]
            ),
            SelectQuery(
                projection: .all,
                source: .graphPattern(.basic([])),
                having: .aggregate(.count(nil, distinct: false))
            ),
            SelectQuery(
                projection: .all,
                source: .graphPattern(.basic([])),
                orderBy: [
                    SortKey(
                        .aggregate(.count(nil, distinct: false)),
                        direction: .ascending
                    )
                ]
            ),
        ]

        for query in queries {
            try SPARQLSemanticValidator.validate(query)
        }
    }

    @Test("BIND and SELECT AS cannot replace source variables")
    func assignmentTargetCollisionIsInvalid() {
        let pattern = GraphPattern.basic([
            triple(subject: .variable("value"))
        ])
        let queries = [
            SelectQuery(
                projection: .all,
                source: .graphPattern(
                    .bind(
                        pattern,
                        variable: "value",
                        expression: .literal(.int(1))
                    )
                )
            ),
            SelectQuery(
                projection: .items([
                    ProjectionItem(.literal(.int(1)), alias: "value")
                ]),
                source: .graphPattern(pattern)
            ),
        ]

        for query in queries {
            #expect(
                throws: SPARQLSemanticValidationError
                    .variableAlreadyInScope("value")
            ) {
                try SPARQLSemanticValidator.validate(query)
            }
        }
    }

    @Test("Grouped projection exposes only group variables and aggregates")
    func groupedProjectionScopeIsValidated() {
        let query = SelectQuery(
            projection: .items([
                ProjectionItem(.variable(Variable("notGrouped")))
            ]),
            source: .graphPattern(.basic([])),
            groupBy: [.variable(Variable("grouped"))]
        )

        #expect(
            throws: SPARQLSemanticValidationError
                .projectionVariableNotGrouped("notGrouped")
        ) {
            try SPARQLSemanticValidator.validate(query)
        }
    }

    @Test("Every raw SPARQL IRI boundary validates before execution")
    func rawIRIBoundariesAreValidated() {
        let select = SelectQuery(
            projection: .all,
            source: .service(
                endpoint: "relative/service",
                pattern: .basic([]),
                silent: false
            ),
            dataset: .explicit(
                defaultGraphs: ["urn:valid"],
                namedGraphs: []
            )
        )
        #expect(
            throws: SPARQLSemanticValidationError.invalidIRI(
                "relative/service",
                .missingScheme
            )
        ) {
            try SPARQLSemanticValidator.validate(select)
        }

        let update = SPARQLUpdateRequest(
            firstOperation: .load(
                LoadQuery(source: "relative/source")
            )
        )
        #expect(
            throws: SPARQLSemanticValidationError.invalidIRI(
                "relative/source",
                .missingScheme
            )
        ) {
            try SPARQLSemanticValidator.validate(update)
        }
    }

    @Test("RDF literal annotations validate at the canonical gate")
    func literalAnnotationsAreValidated() {
        let typed = SelectQuery(
            projection: .items([
                ProjectionItem(
                    .literal(
                        .typedLiteral(
                            value: "value",
                            datatype: "relative/datatype"
                        )
                    ),
                    alias: "value"
                )
            ]),
            source: .graphPattern(.basic([]))
        )
        #expect(throws: SPARQLSemanticValidationError.self) {
            try SPARQLSemanticValidator.validate(typed)
        }

        let language = SelectQuery(
            projection: .items([
                ProjectionItem(
                    .literal(.langLiteral(value: "value", language: "_")),
                    alias: "value"
                )
            ]),
            source: .graphPattern(.basic([]))
        )
        #expect(
            throws: SPARQLSemanticValidationError.invalidLanguageTag(
                "_",
                .invalidSyntax
            )
        ) {
            try SPARQLSemanticValidator.validate(language)
        }
    }

    @Test("Variable scope includes GRAPH selectors, aliases, and UNDEF")
    func variableScopeIsLevelAware() {
        let graph = GraphPattern.graph(
            name: .variable("graph"),
            pattern: .basic([triple(subject: .variable("subject"))])
        )
        #expect(
            graph.variableScope.visibleVariables == ["graph", "subject", "object"]
        )
        #expect(graph.variableScope.definitelyBoundVariables.contains("graph"))

        let values = GraphPattern.values(
            variables: ["left", "right"],
            bindings: [[.int(1), nil]]
        )
        #expect(values.variableScope.visibleVariables == ["left", "right"])
        #expect(values.variableScope.definitelyBoundVariables == ["left"])

        let subquery = GraphPattern.subquery(
            SelectQuery(
                projection: .items([
                    ProjectionItem(.literal(.int(1)), alias: "alias")
                ]),
                source: .graphPattern(.basic([]))
            )
        )
        #expect(subquery.variableScope.visibleVariables == ["alias"])
    }

    @Test("The maximum structural nesting depth is accepted")
    func maximumStructuralDepthIsAccepted() throws {
        let pattern = GraphPattern.basic([
            triple(subject: nestedTerm(levels: 6))
        ])

        try SPARQLSemanticValidator.validate(
            pattern,
            limits: QueryStructuralLimits(
                maximumNestingDepth: 8
            )
        )
    }

    @Test("Structural nesting depth above the maximum is rejected")
    func excessiveStructuralDepthIsRejected() {
        let pattern = GraphPattern.basic([
            triple(subject: nestedTerm(levels: 7))
        ])

        #expect(
            throws: SPARQLSemanticValidationError.structural(
                .resourceLimitExceeded(
                    resource: .nestingDepth,
                    actual: 9,
                    maximum: 8
                )
            )
        ) {
            try SPARQLSemanticValidator.validate(
                pattern,
                limits: QueryStructuralLimits(
                    maximumNestingDepth: 8
                )
            )
        }
    }

    @Test("The maximum VALUES cell count is accepted")
    func maximumValuesCellCountIsAccepted() throws {
        let pattern = GraphPattern.values(
            variables: ["left", "right"],
            bindings: [
                [.int(1), .int(2)],
                [.int(3), .int(4)],
            ]
        )

        try SPARQLSemanticValidator.validate(
            pattern,
            limits: QueryStructuralLimits(maximumValuesCells: 4)
        )
    }

    @Test("The maximum VALUES row and variable counts are accepted")
    func maximumValuesDimensionsAreAccepted() throws {
        let pattern = GraphPattern.values(
            variables: ["left", "right"],
            bindings: [[nil, nil], [nil, nil]]
        )

        try SPARQLSemanticValidator.validate(
            pattern,
            limits: QueryStructuralLimits(
                maximumValuesRows: 2,
                maximumValuesVariables: 2
            )
        )
    }

    @Test("VALUES rows above the maximum are rejected even with zero cells")
    func excessiveValuesRowsAreRejected() {
        let pattern = GraphPattern.values(
            variables: [],
            bindings: [[], [], []]
        )

        #expect(
            throws: SPARQLSemanticValidationError.structural(
                .resourceLimitExceeded(
                    resource: .valuesRows,
                    actual: 3,
                    maximum: 2
                )
            )
        ) {
            try SPARQLSemanticValidator.validate(
                pattern,
                limits: QueryStructuralLimits(maximumValuesRows: 2)
            )
        }
    }

    @Test("VALUES variables above the maximum are rejected")
    func excessiveValuesVariablesAreRejected() {
        let pattern = GraphPattern.values(
            variables: ["first", "second", "third"],
            bindings: []
        )

        #expect(
            throws: SPARQLSemanticValidationError.structural(
                .resourceLimitExceeded(
                    resource: .valuesVariables,
                    actual: 3,
                    maximum: 2
                )
            )
        ) {
            try SPARQLSemanticValidator.validate(
                pattern,
                limits: QueryStructuralLimits(maximumValuesVariables: 2)
            )
        }
    }

    @Test("VALUES cells above the maximum are rejected")
    func excessiveValuesCellCountIsRejected() {
        let pattern = GraphPattern.values(
            variables: ["left", "right"],
            bindings: [
                [.int(1), .int(2)],
                [.int(3), .int(4)],
                [.int(5)],
            ]
        )

        #expect(
            throws: SPARQLSemanticValidationError.structural(
                .resourceLimitExceeded(
                    resource: .valuesCells,
                    actual: 5,
                    maximum: 4
                )
            )
        ) {
            try SPARQLSemanticValidator.validate(
                pattern,
                limits: QueryStructuralLimits(maximumValuesCells: 4)
            )
        }
    }

    @Test("The maximum reified triple expansion count is accepted")
    func maximumReifiedTripleExpansionCountIsAccepted() throws {
        let pattern = GraphPattern.basic([
            triple(subject: nestedReifiedTerm(levels: 2))
        ])

        try SPARQLSemanticValidator.validate(
            pattern,
            limits: QueryStructuralLimits(
                maximumReifiedTripleExpansions: 2
            )
        )
    }

    @Test("Reified triple expansions above the maximum are rejected")
    func excessiveReifiedTripleExpansionCountIsRejected() {
        let pattern = GraphPattern.basic([
            triple(subject: nestedReifiedTerm(levels: 3))
        ])

        #expect(
            throws: SPARQLSemanticValidationError.structural(
                .resourceLimitExceeded(
                    resource: .reifiedTripleExpansions,
                    actual: 3,
                    maximum: 2
                )
            )
        ) {
            try SPARQLSemanticValidator.validate(
                pattern,
                limits: QueryStructuralLimits(
                    maximumReifiedTripleExpansions: 2
                )
            )
        }
    }

    private func query(object: SPARQLTerm) -> SelectQuery {
        SelectQuery(
            projection: .all,
            source: .graphPattern(
                .basic([triple(subject: .variable("subject"), object: object)])
            )
        )
    }

    private func modify(whereSubject: SPARQLTerm) -> SPARQLUpdateOperation {
        .modify(
            SPARQLModifyOperation(
                action: .insert([quad(subject: .iri("urn:inserted"))]),
                wherePattern: .basic([triple(subject: whereSubject)])
            )
        )
    }

    private func triple(
        subject: SPARQLTerm,
        object: SPARQLTerm = .variable("object")
    ) -> TriplePattern {
        TriplePattern(
            subject: subject,
            predicate: .iri("urn:predicate"),
            object: object
        )
    }

    private func quad(
        subject: SPARQLTerm,
        object: SPARQLTerm = .literal(.string("value"))
    ) -> Quad {
        Quad(triple: triple(subject: subject, object: object))
    }

    private func nestedTerm(levels: Int) -> SPARQLTerm {
        var term = SPARQLTerm.iri("urn:leaf")
        for level in 0..<levels {
            term = .tripleTerm(
                subject: term,
                predicate: .iri("urn:predicate:\(level)"),
                object: .iri("urn:object:\(level)")
            )
        }
        return term
    }

    private func nestedReifiedTerm(levels: Int) -> SPARQLTerm {
        var term = SPARQLTerm.iri("urn:leaf")
        for level in 0..<levels {
            term = .reifiedTriple(
                subject: term,
                predicate: .iri("urn:predicate:\(level)"),
                object: .iri("urn:object:\(level)"),
                reifier: .variable("reifier\(level)")
            )
        }
        return term
    }
}

private func fixtureIRI(_ rawValue: String) -> RDFIRI {
    do {
        return try RDFIRI(rawValue)
    } catch {
        preconditionFailure("Invalid RDF IRI fixture: \(rawValue)")
    }
}

private func fixtureBlankNode(
    _ rawValue: String
) -> RDFBlankNodeIdentifier {
    do {
        return try RDFBlankNodeIdentifier(rawValue)
    } catch {
        preconditionFailure("Invalid blank-node fixture: \(rawValue)")
    }
}
