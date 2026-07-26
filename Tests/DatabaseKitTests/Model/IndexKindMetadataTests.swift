import DatabaseKit
import DatabaseTypes
import Testing

@Suite("Index Kind Metadata")
struct IndexKindMetadataTests {
    @Test("Integer metadata accepts every exact FieldValue integer width")
    func integerMetadataPreservesExactIntegerSemantics() throws {
        let cases: [(FieldValue, Int)] = [
            (.int8(-8), -8),
            (.int16(-16), -16),
            (.int32(-32), -32),
            (.int64(-64), -64),
            (.uint8(8), 8),
            (.uint16(16), 16),
            (.uint32(32), 32),
            (.uint64(64), 64),
        ]

        for (value, expected) in cases {
            let metadata = makeMetadata(["value": value])
            #expect(try metadata.requireInt("value") == expected)
        }
    }

    @Test("Integer metadata rejects values outside the platform Int domain")
    func integerMetadataRejectsOverflow() {
        let metadata = makeMetadata(["value": .uint64(.max)])

        #expect(throws: IndexKindMetadataError.self) {
            try metadata.requireInt("value")
        }
    }

    @Test("Array metadata rejects a mixed element domain")
    func arrayMetadataRejectsMixedElements() {
        let metadata = makeMetadata([
            "values": .array([.string("first"), .int64(2)])
        ])

        #expect(throws: IndexKindMetadataError.self) {
            try metadata.requireStringArray("values")
        }
    }

    @Test("Built-in definition rejects an extension identifier")
    func builtInDefinitionRejectsExtensionIdentifier() {
        let metadata = IndexKindMetadata(
            identifier: "com.example.custom",
            subspaceStructure: .flat,
            fields: [],
            metadata: [:]
        )

        #expect(
            throws: IndexKindMetadataError.unknownIdentifier(
                "com.example.custom"
            )
        ) {
            _ = try IndexDefinition(metadata: metadata)
        }
    }

    @Test("Built-in definition rejects unexpected configuration")
    func builtInDefinitionRejectsUnexpectedConfiguration() {
        let metadata = IndexKindMetadata(
            identifier: "scalar",
            subspaceStructure: .flat,
            fields: [
                IndexFieldMetadata(
                    identity: FieldIdentity(name: "value", number: 1)
                )
            ],
            metadata: ["dimensions": .int64(3)]
        )

        #expect(
            throws: IndexKindMetadataError.unexpectedMetadata(
                identifier: "scalar",
                key: "dimensions"
            )
        ) {
            _ = try IndexDefinition(metadata: metadata)
        }
    }

    @Test("Property graph restores an implicit edge label")
    func propertyGraphRestoresImplicitEdgeLabel() throws {
        let metadata = IndexKindMetadata(
            identifier: "graph",
            subspaceStructure: .hierarchical,
            fields: [
                IndexFieldMetadata(
                    identity: FieldIdentity(name: "source", number: 1)
                ),
                IndexFieldMetadata(
                    identity: FieldIdentity(name: "target", number: 2)
                ),
            ],
            metadata: [
                "strategy": .string("adjacency"),
                "hasEdgeField": .bool(false),
                "hasGraphField": .bool(false),
            ]
        )

        let definition = try IndexDefinition(metadata: metadata)
        guard case .graph(let strategy, let label) = definition else {
            Issue.record("Expected graph definition")
            return
        }
        #expect(strategy == .adjacency)
        #expect(label == .implicit)
    }

    @Test("OWL class metadata restores only a valid RDF graph name")
    func owlClassMetadataRestoresGraphName() throws {
        let graph = try RDFGraphName(
            iri: "https://example.org/graphs/people"
        )
        let metadata = IndexKindMetadata(
            identifier: "owl_class_rdf",
            subspaceStructure: .hierarchical,
            fields: [],
            metadata: [
                "individualIRIBase": .string(
                    "https://example.org/people/"
                ),
                "graph": .rdfTerm(graph.term),
            ]
        )

        let decoded = try OWLClassRDFIndexMetadata(canonical: metadata)
        #expect(decoded.graph == graph)

        let invalid = IndexKindMetadata(
            identifier: "owl_class_rdf",
            subspaceStructure: .hierarchical,
            fields: [],
            metadata: [
                "individualIRIBase": .string(
                    "https://example.org/people/"
                ),
                "graph": .rdfTerm(
                    .literal(
                        RDFLiteral(
                            lexicalForm: "not a graph name",
                            datatype: .xsdString
                        )
                    )
                ),
            ]
        )
        #expect(
            throws: IndexKindMetadataError.invalidMetadata(
                identifier: "owl_class_rdf",
                key: "graph"
            )
        ) {
            _ = try OWLClassRDFIndexMetadata(canonical: invalid)
        }
    }

    @Test("Autocomplete accepts scalar and array string fields")
    func autocompleteAcceptsStringFields() throws {
        let definition = IndexDefinition.autocomplete(
            minPrefixLength: 2,
            maxPrefixLength: 12
        )
        let fields = [
            IndexFieldMetadata(
                identity: FieldIdentity(name: "title", number: 1)
            ),
            IndexFieldMetadata(
                identity: FieldIdentity(name: "aliases", number: 2)
            ),
        ]
        let metadata = try definition.kindMetadata(
            fields: fields,
            schemas: [
                FieldSchema(
                    name: "title",
                    fieldNumber: 1,
                    type: .string
                ),
                FieldSchema(
                    name: "aliases",
                    fieldNumber: 2,
                    type: .string,
                    isArray: true
                ),
            ]
        )

        #expect(metadata.identifier == "autocomplete")
        #expect(metadata.fields == fields)
        #expect(metadata.metadata["minPrefixLength"] == .int64(2))
        #expect(metadata.metadata["maxPrefixLength"] == .int64(12))
        #expect(try IndexDefinition(metadata: metadata) == definition)
    }

    @Test("Autocomplete rejects invalid prefix bounds")
    func autocompleteRejectsInvalidPrefixBounds() {
        let field = IndexFieldMetadata(
            identity: FieldIdentity(name: "title", number: 1)
        )
        let schema = FieldSchema(
            name: "title",
            fieldNumber: 1,
            type: .string
        )

        #expect(throws: IndexValidationError.self) {
            _ = try IndexDefinition.autocomplete(
                minPrefixLength: 0,
                maxPrefixLength: 12
            ).kindMetadata(fields: [field], schemas: [schema])
        }
        #expect(throws: IndexValidationError.self) {
            _ = try IndexDefinition.autocomplete(
                minPrefixLength: 4,
                maxPrefixLength: 3
            ).kindMetadata(fields: [field], schemas: [schema])
        }
    }

    @Test("Autocomplete rejects non-string fields")
    func autocompleteRejectsNonStringFields() {
        #expect(throws: IndexValidationError.self) {
            _ = try IndexDefinition.autocomplete().kindMetadata(
                fields: [
                    IndexFieldMetadata(
                        identity: FieldIdentity(name: "count", number: 1)
                    )
                ],
                schemas: [
                    FieldSchema(
                        name: "count",
                        fieldNumber: 1,
                        type: .int64
                    )
                ]
            )
        }
    }

    private func makeMetadata(
        _ values: [String: FieldValue]
    ) -> IndexKindMetadata {
        IndexKindMetadata(
            identifier: "test",
            subspaceStructure: .flat,
            fields: [
                IndexFieldMetadata(
                    identity: FieldIdentity(name: "value", number: 1)
                )
            ],
            metadata: values
        )
    }
}
