import DatabaseTypes
import DatabaseValue
import DatabaseWire
import QueryIR
import Testing

@Suite("QueryIR wire codec")
struct QueryIRWireCodecTests {
    @Test("mixed basic graph patterns round-trip without splitting blank-node scope")
    func mixedBasicGraphPatternRoundTrips() throws {
        let pathPredicate = try RDFPredicateIRI("urn:calendar:related")
        let basicGraphPattern = BasicGraphPattern(
            elements: [
                .triple(
                    TriplePattern(
                        subject: .blankNode("shared"),
                        predicate: .iri("urn:calendar:title"),
                        object: .variable("title")
                    )
                ),
                .propertyPath(
                    SPARQLPropertyPathPattern(
                        subject: .blankNode("shared"),
                        path: .oneOrMore(.iri(pathPredicate)),
                        object: .variable("related")
                    )
                ),
            ]
        )
        let original = QueryStatement.select(
            SelectQuery(
                projection: .all,
                source: .graphPattern(.basic(basicGraphPattern))
            )
        )

        let encoded = try QueryIRWireCodec.encode(original)
        let decoded = try QueryIRWireCodec.decode(encoded)

        #expect(decoded == original)
        guard case .select(let query) = decoded,
              case .graphPattern(.basic(let decodedPattern)) = query.source else {
            Issue.record("Expected a decoded mixed basic graph pattern")
            return
        }
        #expect(decodedPattern.elements == basicGraphPattern.elements)
        #expect(throws: BasicGraphPatternError.propertyPathAtIndex(1)) {
            _ = try decodedPattern.triplePatterns()
        }
    }

    @Test("every statement family round-trips through the canonical codec")
    func everyStatementFamilyRoundTrips() throws {
        let triple = TriplePattern(
            subject: .variable("event"),
            predicate: .iri("urn:calendar:startsAt"),
            object: .variable("date")
        )
        let graphPattern = GraphPattern.basic([triple])
        let select = SelectQuery(
            projection: .items([
                ProjectionItem(.variable(Variable("event")), alias: "identifier"),
                ProjectionItem(.literal(.uint(UInt64.max)), alias: "unsigned"),
                ProjectionItem(
                    .literal(.decimal(coefficient: 12_345, scale: 2)),
                    alias: "decimal"
                ),
            ]),
            source: .graphPattern(graphPattern),
            accessPath: .index(
                IndexScanSource(
                    indexName: "eventGraph",
                    kindIdentifier: "graph",
                    parameters: ["snapshot": .string("active")]
                )
            ),
            filter: .greaterThan(.variable(Variable("date")), .string("2026-07-16")),
            orderBy: [SortKey(.variable(Variable("date")))],
            limit: 50
        )
        let table = TableRef(
            schema: "calendar",
            table: "events",
            alias: "event",
            partitions: try FieldObject([
                (
                    key: "runID",
                    value: .string("run-2026-07-17")
                ),
            ])
        )
        let statements: [QueryStatement] = [
            .select(select),
            .insert(
                InsertQuery(
                    target: table,
                    columns: ["id", "title"],
                    source: .values([[.string("event-1"), .string("Festival")]]),
                    onConflict: .doNothing,
                    returning: [ProjectionItem.column("id")]
                )
            ),
            .update(
                UpdateQuery(
                    target: table,
                    assignments: [Assignment(column: "title", value: .string("Updated"))],
                    filter: .equal(.col("id"), .string("event-1"))
                )
            ),
            .delete(
                DeleteQuery(
                    target: table,
                    filter: .equal(.col("id"), .string("event-1"))
                )
            ),
            .createGraph(
                CreateGraphStatement(
                    graphName: "calendarGraph",
                    ifNotExists: true,
                    vertexTables: [
                        VertexTableDefinition(
                            tableName: "events",
                            keyColumns: ["id"],
                            labelExpression: .single("Event"),
                            propertiesSpec: .all
                        ),
                    ],
                    edgeTables: []
                )
            ),
            .dropGraph("calendarGraph"),
            .sparqlUpdate(
                SPARQLUpdateRequest(
                    firstOperation: .insertData(
                        InsertDataQuery(quads: [Quad(triple: triple)])
                    ),
                    additionalOperations: [
                        .deleteData(
                            DeleteDataQuery(quads: [Quad(triple: triple)])
                        ),
                        .modify(
                            SPARQLModifyOperation(
                                withGraph: "urn:active",
                                action: .deleteAndInsert(
                                    delete: [Quad(triple: triple)],
                                    insert: [
                                        Quad(
                                            graph: .iri("urn:active"),
                                            triple: triple
                                        ),
                                    ]
                                ),
                                using: [
                                    GraphRef(
                                        iri: "urn:staged",
                                        isNamed: true
                                    ),
                                ],
                                wherePattern: graphPattern
                            )
                        ),
                        .deleteWhere(
                            DeleteWhereQuery(
                                pattern: [
                                    Quad(
                                        graph: .variable("graph"),
                                        triple: triple
                                    ),
                                ]
                            )
                        ),
                        .load(
                            LoadQuery(
                                source: "https://example.invalid/calendar.ttl",
                                destination: "urn:staged"
                            )
                        ),
                        .clear(
                            ClearQuery(
                                target: .graph("urn:staged"),
                                silent: true
                            )
                        ),
                        .createGraph(
                            CreateSPARQLGraphQuery(
                                graph: "urn:staged",
                                silent: true
                            )
                        ),
                        .drop(DropQuery(target: .all)),
                        .graphTransfer(
                            GraphTransferQuery(
                                operation: .add,
                                source: .default,
                                destination: .graph("urn:staged"),
                                silent: true
                            )
                        ),
                        .graphTransfer(
                            GraphTransferQuery(
                                operation: .copy,
                                source: .graph("urn:staged"),
                                destination: .default
                            )
                        ),
                        .graphTransfer(
                            GraphTransferQuery(
                                operation: .move,
                                source: .graph("urn:staged"),
                                destination: .graph("urn:active")
                            )
                        ),
                    ]
                )
            ),
            .construct(
                ConstructQuery(
                    template: [triple],
                    pattern: graphPattern,
                    dataset: .explicit(
                        defaultGraphs: ["urn:active"],
                        namedGraphs: ["urn:staged"]
                    ),
                    modifiers: SPARQLSolutionModifiers(
                        orderBy: [SortKey(.variable(Variable("event")))],
                        limit: 10
                    )
                )
            ),
            .ask(
                AskQuery(
                    pattern: graphPattern,
                    dataset: .explicit(
                        defaultGraphs: ["urn:active"],
                        namedGraphs: []
                    ),
                    modifiers: SPARQLSolutionModifiers(offset: 1)
                )
            ),
            .describe(
                DescribeQuery(
                    selection: .resources(
                        first: .variable("event"),
                        additional: []
                    ),
                    pattern: graphPattern,
                    dataset: .explicit(
                        defaultGraphs: [],
                        namedGraphs: ["urn:staged"]
                    ),
                    modifiers: SPARQLSolutionModifiers(limit: 5)
                )
            ),
        ]

        for statement in statements {
            #expect(try QueryIRWireCodec.decode(QueryIRWireCodec.encode(statement)) == statement)
        }
    }

    @Test("graph transfer has a stable compact golden vector")
    func graphTransferGoldenVector() throws {
        let statement = QueryStatement.sparqlUpdate(
            SPARQLUpdateRequest(
                firstOperation: .graphTransfer(
                    GraphTransferQuery(
                        operation: .add,
                        source: .default,
                        destination: .default
                    )
                )
            )
        )
        let encoded = try QueryIRWireCodec.encode(statement)

        #expect(encoded == [6, 1, 0, 0, 0, 8, 0, 0, 0, 0])
        #expect(try QueryIRWireCodec.decode(encoded) == statement)
    }

    @Test("CLEAR and DROP share every canonical graph-store target")
    func graphStoreTargetsRoundTrip() throws {
        let targets: [SPARQLGraphTarget] = [
            .graph("urn:graph"),
            .default,
            .named,
            .all,
        ]
        for target in targets {
            let clear = QueryStatement.sparqlUpdate(
                SPARQLUpdateRequest(
                    firstOperation: .clear(
                        ClearQuery(target: target, silent: true)
                    )
                )
            )
            let drop = QueryStatement.sparqlUpdate(
                SPARQLUpdateRequest(
                    firstOperation: .drop(
                        DropQuery(target: target, silent: true)
                    )
                )
            )
            #expect(
                try QueryIRWireCodec.decode(QueryIRWireCodec.encode(clear))
                    == clear
            )
            #expect(
                try QueryIRWireCodec.decode(QueryIRWireCodec.encode(drop))
                    == drop
            )
        }
    }

    @Test("SPARQL Update request preserves non-empty operation order")
    func sparqlUpdateSequencePreservesOrder() throws {
        let request = SPARQLUpdateRequest(
            firstOperation: .load(
                LoadQuery(source: "urn:source", destination: "urn:stage")
            ),
            additionalOperations: [
                .clear(ClearQuery(target: .default)),
                .drop(DropQuery(target: .graph("urn:old"), silent: true)),
            ]
        )
        let statement = QueryStatement.sparqlUpdate(request)
        let decoded = try QueryIRWireCodec.decode(
            QueryIRWireCodec.encode(statement)
        )

        guard case .sparqlUpdate(let decodedRequest) = decoded else {
            Issue.record("Expected a SPARQL Update request")
            return
        }
        #expect(decodedRequest.count == 3)
        #expect(decodedRequest[0] == request[0])
        #expect(decodedRequest[1] == request[1])
        #expect(decodedRequest[2] == request[2])
    }

    @Test("every SPARQL Modify action round-trips")
    func sparqlModifyActionsRoundTrip() throws {
        let quad = Quad(
            triple: TriplePattern(
                subject: .variable("subject"),
                predicate: .iri("urn:predicate"),
                object: .variable("object")
            )
        )
        let actions: [SPARQLModifyAction] = [
            .delete([quad]),
            .insert([quad]),
            .deleteAndInsert(delete: [quad], insert: [quad]),
        ]

        for action in actions {
            let statement = QueryStatement.sparqlUpdate(
                SPARQLUpdateRequest(
                    firstOperation: .modify(
                        SPARQLModifyOperation(
                            action: action,
                            wherePattern: .basic([quad.triple])
                        )
                    )
                )
            )
            #expect(
                try QueryIRWireCodec.decode(QueryIRWireCodec.encode(statement))
                    == statement
            )
        }
    }

    @Test("ASK has a stable compact golden vector")
    func askGoldenVector() throws {
        let statement = QueryStatement.ask(AskQuery(pattern: .basic([])))
        let encoded = try QueryIRWireCodec.encode(statement)

        #expect(encoded == [
            8,
            0, 0, 0, 0, 0,
            0,
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0,
            0,
            0,
        ])
        #expect(try QueryIRWireCodec.decode(encoded) == statement)
    }

    @Test("typed query operation embeds QueryIR without an opaque payload")
    func queryOperationEmbedsTypedIR() throws {
        let statement = QueryStatement.ask(AskQuery(pattern: .basic([])))
        let request = QueryExecuteOperation.Request(
            input: .ir(statement),
            graphPartitions: try FieldObject([
                (
                    key: "runID",
                    value: .string("run-2026-07-17")
                ),
            ])
        )

        let encoded = try DatabaseEnvelopeCodec.encode(request)
        let decoded = try DatabaseEnvelopeCodec.decode(
            QueryExecuteOperation.Request.self,
            from: encoded
        )

        #expect(decoded == request)
    }

    @Test("parameter references round-trip without becoming variables")
    func parameterReferencesRoundTrip() throws {
        let statement = QueryStatement.select(
            SelectQuery(
                projection: .items([
                    ProjectionItem(.parameter(.position(1))),
                    ProjectionItem(.parameter(.name("title"))),
                ]),
                source: .table(TableRef("Event"))
            )
        )

        let encoded = try QueryIRWireCodec.encode(statement)
        #expect(try QueryIRWireCodec.decode(encoded) == statement)
    }

    @Test("GRAPH_TABLE aliases survive the canonical wire boundary")
    func graphTableAliasRoundTrips() throws {
        let statement = QueryStatement.select(
            SelectQuery(
                projection: .all,
                source: .graphTable(
                    GraphTableSource(
                        graphName: "social",
                        matchPattern: MatchPattern(
                            paths: [
                                PathPattern(
                                    elements: [
                                        .node(NodePattern(variable: "person")),
                                    ]
                                ),
                            ]
                        ),
                        alias: "people"
                    )
                )
            )
        )

        let encoded = try QueryIRWireCodec.encode(statement)

        #expect(try QueryIRWireCodec.decode(encoded) == statement)
    }

    @Test("invalid parameter references are rejected by the wire codec")
    func invalidParameterReferencesAreRejected() {
        let invalidPosition = QueryStatement.select(
            SelectQuery(
                projection: .items([ProjectionItem(.parameter(.position(0)))]),
                source: .table(TableRef("Event"))
            )
        )
        let emptyName = QueryStatement.select(
            SelectQuery(
                projection: .items([ProjectionItem(.parameter(.name("")))]),
                source: .table(TableRef("Event"))
            )
        )

        #expect(throws: DatabaseWireError.invalidParameterPosition(0)) {
            _ = try QueryIRWireCodec.encode(invalidPosition)
        }
        #expect(throws: DatabaseWireError.emptyParameterName) {
            _ = try QueryIRWireCodec.encode(emptyName)
        }
    }

    @Test("SPARQL variable names are canonical at both wire boundaries")
    func invalidSPARQLVariableNamesAreRejected() throws {
        let invalid = QueryStatement.select(
            SelectQuery(
                projection: .all,
                source: .graphPattern(
                    .basic([
                        TriplePattern(
                            subject: .variable("?value"),
                            predicate: .iri("urn:predicate"),
                            object: .iri("urn:object")
                        )
                    ])
                )
            )
        )
        #expect(
            throws: DatabaseWireError.invalidSPARQLVariableName("?value")
        ) {
            _ = try QueryIRWireCodec.encode(invalid)
        }

        let valid = QueryStatement.select(
            SelectQuery(
                projection: .all,
                source: .graphPattern(
                    .basic([
                        TriplePattern(
                            subject: .variable("Z"),
                            predicate: .iri("urn:predicate"),
                            object: .iri("urn:object")
                        )
                    ])
                )
            )
        )
        var bytes = Array(try QueryIRWireCodec.encode(valid))
        let matchingIndices = bytes.indices.filter { bytes[$0] == 0x5A }
        guard matchingIndices.count == 1,
              let variableByteIndex = matchingIndices.first else {
            Issue.record("Expected one unique variable byte in the encoded query")
            return
        }
        bytes[variableByteIndex] = 0x3F

        #expect(
            throws: DatabaseWireError.invalidSPARQLVariableName("?")
        ) {
            _ = try QueryIRWireCodec.decode(ByteString(bytes))
        }
    }

    @Test("SPARQL IRIs are validated at both wire boundaries")
    func invalidSPARQLIRIsAreRejected() throws {
        let invalidStatements: [QueryStatement] = [
            .select(
                SelectQuery(
                    projection: .all,
                    source: .graphPattern(.basic([])),
                    dataset: .explicit(
                        defaultGraphs: ["relative"],
                        namedGraphs: []
                    )
                )
            ),
            .select(
                SelectQuery(
                    projection: .all,
                    source: .service(
                        endpoint: "relative",
                        pattern: .basic([]),
                        silent: false
                    )
                )
            ),
            .sparqlUpdate(
                SPARQLUpdateRequest(
                    firstOperation: .load(
                        LoadQuery(source: "relative")
                    )
                )
            ),
            .sparqlUpdate(
                SPARQLUpdateRequest(
                    firstOperation: .modify(
                        SPARQLModifyOperation(
                            withGraph: "relative",
                            action: .insert([]),
                            wherePattern: .basic([])
                        )
                    )
                )
            ),
            .sparqlUpdate(
                SPARQLUpdateRequest(
                    firstOperation: .clear(
                        ClearQuery(target: .graph("relative"))
                    )
                )
            ),
            .sparqlUpdate(
                SPARQLUpdateRequest(
                    firstOperation: .createGraph(
                        CreateSPARQLGraphQuery(graph: "relative")
                    )
                )
            ),
            .sparqlUpdate(
                SPARQLUpdateRequest(
                    firstOperation: .graphTransfer(
                        GraphTransferQuery(
                            operation: .copy,
                            source: .graph("relative"),
                            destination: .default
                        )
                    )
                )
            ),
        ]

        for statement in invalidStatements {
            #expect(throws: DatabaseWireError.invalidRDFIRI("relative")) {
                _ = try QueryIRWireCodec.encode(statement)
            }
        }

        let valid = QueryStatement.select(
            SelectQuery(
                projection: .all,
                source: .graphPattern(.basic([])),
                dataset: .explicit(
                    defaultGraphs: ["urn:valid"],
                    namedGraphs: []
                )
            )
        )
        let invalidBytes = try replacingUniqueASCII(
            "urn:valid",
            in: QueryIRWireCodec.encode(valid),
            with: "urn_valid"
        )

        #expect(
            throws: DatabaseWireError.invalidRDFIRI("urn_valid")
        ) {
            _ = try QueryIRWireCodec.decode(invalidBytes)
        }
    }

    @Test("RDF literal annotations are canonical at both wire boundaries")
    func invalidRDFLiteralAnnotationsAreRejected() throws {
        let invalidLiterals: [(Literal, DatabaseWireError)] = [
            (.iri("relative"), .invalidRDFIRI("relative")),
            (
                .typedLiteral(value: "value", datatype: "relative"),
                .invalidRDFDatatypeIRI
            ),
            (
                .langLiteral(value: "value", language: "not_a_tag"),
                .invalidRDFLanguageTag
            ),
            (
                .langLiteral(value: "value", language: "EN"),
                .nonCanonicalRDFLanguageTag
            ),
            (
                .dirLangLiteral(
                    value: "value",
                    language: "en",
                    direction: "bad"
                ),
                .invalidRDFDirectionValue("bad")
            ),
        ]

        for (literal, expectedError) in invalidLiterals {
            let statement = statement(projecting: literal)
            #expect(throws: expectedError) {
                _ = try QueryIRWireCodec.encode(statement)
            }
        }

        let validLanguage = statement(
            projecting: .langLiteral(value: "value", language: "en")
        )
        let invalidLanguageBytes = try replacingUniqueASCII(
            "en",
            in: QueryIRWireCodec.encode(validLanguage),
            with: "EN"
        )
        #expect(throws: DatabaseWireError.nonCanonicalRDFLanguageTag) {
            _ = try QueryIRWireCodec.decode(invalidLanguageBytes)
        }

        let validDirection = statement(
            projecting: .dirLangLiteral(
                value: "value",
                language: "en",
                direction: "ltr"
            )
        )
        let invalidDirectionBytes = try replacingUniqueASCII(
            "ltr",
            in: QueryIRWireCodec.encode(validDirection),
            with: "bad"
        )
        #expect(
            throws: DatabaseWireError.invalidRDFDirectionValue("bad")
        ) {
            _ = try QueryIRWireCodec.decode(invalidDirectionBytes)
        }
    }

    @Test("invalid tags and excessive nesting are rejected deterministically")
    func invalidFramesAreRejected() throws {
        #expect(throws: DatabaseWireError.invalidValueTag(255)) {
            _ = try QueryIRWireCodec.decode([255])
        }
        #expect(throws: DatabaseWireError.emptySPARQLUpdateRequest) {
            _ = try QueryIRWireCodec.decode([6, 0, 0, 0, 0])
        }
        let zeroCollectionLimit = try DatabaseWireLimits(
            maximumFrameBytes: 64,
            maximumStringBytes: 64,
            maximumByteStringBytes: 64,
            maximumCollectionCount: 0,
            maximumNestingDepth: 8,
            maximumObjectCount: 8
        )
        #expect(throws: DatabaseWireError.collectionTooLarge(
            actual: 1,
            maximum: 0
        )) {
            _ = try QueryIRWireCodec.decode(
                [6, 1, 0, 0, 0, 8, 0, 0, 0, 0],
                limits: zeroCollectionLimit
            )
        }
        #expect(throws: DatabaseWireError.invalidValueTag(255)) {
            _ = try QueryIRWireCodec.decode([6, 1, 0, 0, 0, 255])
        }
        #expect(throws: DatabaseWireError.invalidValueTag(255)) {
            _ = try QueryIRWireCodec.decode([6, 1, 0, 0, 0, 2, 0, 255])
        }
        #expect(throws: DatabaseWireError.invalidValueTag(255)) {
            _ = try QueryIRWireCodec.decode([6, 1, 0, 0, 0, 5, 255])
        }
        #expect(throws: DatabaseWireError.invalidValueTag(255)) {
            _ = try QueryIRWireCodec.decode([6, 1, 0, 0, 0, 8, 255])
        }
        #expect(throws: DatabaseWireError.invalidValueTag(255)) {
            _ = try QueryIRWireCodec.decode([6, 1, 0, 0, 0, 8, 0, 255])
        }
        #expect(throws: DatabaseWireError.invalidValueTag(255)) {
            _ = try QueryIRWireCodec.decode([6, 1, 0, 0, 0, 8, 0, 0, 255])
        }
        #expect(throws: DatabaseWireError.truncated) {
            _ = try QueryIRWireCodec.decode([
                6, 2, 0, 0, 0,
                8, 0, 0, 0, 0,
            ])
        }

        let nestedPath = PropertyPath.inverse(
            .inverse(
                .inverse(
                    .iri(try RDFPredicateIRI("urn:edge"))
                )
            )
        )
        let statement = QueryStatement.select(
            SelectQuery(
                projection: .all,
                source: .graphPattern(
                    .propertyPath(
                        subject: .variable("source"),
                        path: nestedPath,
                        object: .variable("target")
                    )
                )
            )
        )
        let encoded = try QueryIRWireCodec.encode(statement)
        let limits = try DatabaseWireLimits(
            maximumFrameBytes: 4_096,
            maximumStringBytes: 128,
            maximumByteStringBytes: 128,
            maximumCollectionCount: 128,
            maximumNestingDepth: 3,
            maximumObjectCount: 128
        )

        #expect(throws: DatabaseWireError.self) {
            _ = try QueryIRWireCodec.decode(encoded, limits: limits)
        }
    }

    @Test("deep expressions use bounded iterative wire traversal")
    func deepExpressionsUseIterativeWireTraversal() throws {
        var expression = Expression.literal(.int(1))
        for _ in 0..<256 {
            expression = .not(expression)
        }
        let statement = QueryStatement.select(
            SelectQuery(
                projection: .items([
                    ProjectionItem(expression, alias: "value"),
                ]),
                source: .graphPattern(.basic([]))
            )
        )
        let permissiveLimits = try DatabaseWireLimits(
            maximumFrameBytes: 1_048_576,
            maximumStringBytes: 1_024,
            maximumByteStringBytes: 1_048_576,
            maximumCollectionCount: 1_024,
            maximumNestingDepth: 1_024,
            maximumObjectCount: 10_000
        )
        let bytes = try QueryIRWireCodec.encode(
            statement,
            limits: permissiveLimits
        )

        let decoded = try QueryIRWireCodec.decode(
            bytes,
            limits: permissiveLimits
        )
        let reencoded = try QueryIRWireCodec.encode(
            decoded,
            limits: permissiveLimits
        )
        #expect(reencoded == bytes)

        let boundedLimits = try DatabaseWireLimits(
            maximumFrameBytes: 1_048_576,
            maximumStringBytes: 1_024,
            maximumByteStringBytes: 1_048_576,
            maximumCollectionCount: 1_024,
            maximumNestingDepth: 64,
            maximumObjectCount: 10_000
        )
        let expected = DatabaseWireError.nestingTooDeep(
            actual: 65,
            maximum: 64
        )
        #expect(throws: expected) {
            _ = try QueryIRWireCodec.encode(statement, limits: boundedLimits)
        }
        #expect(throws: expected) {
            _ = try QueryIRWireCodec.decode(bytes, limits: boundedLimits)
        }
    }

    @Test("property path predicate IRIs and ranges enforce invariants")
    func propertyPathTypesEnforceInvariants() throws {
        #expect(
            throws: RDFIRIError.missingScheme
        ) {
            _ = try RDFPredicateIRI("relative")
        }
        #expect(
            throws: PropertyPathRangeError.maximumBelowMinimum(
                minimum: 3,
                maximum: 2
            )
        ) {
            _ = try PropertyPathRange(minimum: 3, maximum: 2)
        }
    }

    @Test("negated property sets encode direction and deterministic ordering")
    func negatedPropertySetsAreCanonical() throws {
        let alpha = try RDFPredicateIRI("urn:predicate:alpha")
        let beta = try RDFPredicateIRI("urn:predicate:beta")
        let inverse = try RDFPredicateIRI("urn:predicate:inverse")
        let first = try PropertyPathNegatedSet(
            forward: Set([beta, alpha]),
            inverse: Set([inverse])
        )
        let second = try PropertyPathNegatedSet(
            forward: Set([alpha, beta]),
            inverse: Set([inverse])
        )
        let firstStatement = statement(
            path: .negatedPropertySet(first)
        )
        let secondStatement = statement(
            path: .negatedPropertySet(second)
        )

        let firstBytes = try QueryIRWireCodec.encode(firstStatement)
        let secondBytes = try QueryIRWireCodec.encode(secondStatement)

        #expect(firstBytes == secondBytes)
        #expect(try QueryIRWireCodec.decode(firstBytes) == firstStatement)
        #expect(first.reversed.forward == first.inverse)
        #expect(first.reversed.inverse == first.forward)
    }

    @Test("bounded property path round-trips without approximation")
    func boundedPropertyPathRoundTrips() throws {
        let predicate = try RDFPredicateIRI("urn:predicate:next")
        let bounds = try PropertyPathRange(minimum: 2, maximum: 4)
        let original = statement(path: .range(.iri(predicate), bounds))

        let bytes = try QueryIRWireCodec.encode(original)

        #expect(try QueryIRWireCodec.decode(bytes) == original)
    }

    private func statement(path: PropertyPath) -> QueryStatement {
        .select(
            SelectQuery(
                projection: .all,
                source: .graphPattern(
                    .propertyPath(
                        subject: .variable("source"),
                        path: path,
                        object: .variable("target")
                    )
                )
            )
        )
    }

    private func statement(projecting literal: Literal) -> QueryStatement {
        .select(
            SelectQuery(
                projection: .items([
                    ProjectionItem(.literal(literal), alias: "value"),
                ]),
                source: .graphPattern(.basic([]))
            )
        )
    }

    private func replacingUniqueASCII(
        _ source: String,
        in bytes: ByteString,
        with replacement: String
    ) throws -> ByteString {
        let sourceBytes = Array(source.utf8)
        let replacementBytes = Array(replacement.utf8)
        guard sourceBytes.count == replacementBytes.count else {
            Issue.record("Encoded replacement must preserve byte count")
            return bytes
        }

        var result = bytes.copyBytes()
        var matchingOffsets: [Int] = []
        guard result.count >= sourceBytes.count else {
            Issue.record("Encoded payload does not contain the expected ASCII value")
            return bytes
        }
        for offset in 0...(result.count - sourceBytes.count) {
            if result[offset..<(offset + sourceBytes.count)].elementsEqual(
                sourceBytes
            ) {
                matchingOffsets.append(offset)
            }
        }
        guard matchingOffsets.count == 1,
              let offset = matchingOffsets.first else {
            Issue.record("Encoded payload must contain exactly one expected ASCII value")
            return bytes
        }
        result.replaceSubrange(
            offset..<(offset + sourceBytes.count),
            with: replacementBytes
        )
        return ByteString(result)
    }
}
