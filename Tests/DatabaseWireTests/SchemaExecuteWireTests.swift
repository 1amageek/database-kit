import DatabaseKit
import DatabaseTypes
@_spi(DatabaseServer) @testable import DatabaseWire
import Testing

@Suite("Schema execute wire")
struct SchemaExecuteWireTests {
    @Test("complete schema manifest round-trips without losing semantic metadata")
    func completeManifestRoundTrips() throws {
        let emptyManifest = SchemaManifest(
            schema: try Schema(entities: [], version: .init(0, 0, 0))
        )
        #expect(
            try emptyManifest.canonicalBytes() == ByteString([
                0x01, 0x00,
                0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00,
            ])
        )
        #expect(
            try emptyManifest.fingerprint().bytes == ByteString([
                0xaa, 0x25, 0xe1, 0xd5, 0x95, 0xa7, 0x7c, 0x37,
                0x5b, 0x40, 0xb4, 0x79, 0x6e, 0xa4, 0xff, 0x04,
                0x48, 0x90, 0xef, 0xee, 0xbd, 0x4b, 0xd1, 0x5d,
                0x16, 0xd5, 0x43, 0x87, 0xa5, 0xa8, 0xfc, 0x37,
            ])
        )

        let schema = try makeSchema()
        let manifest = SchemaManifest(schema: schema)
        let bytes = try manifest.canonicalBytes()

        let decoded = try SchemaManifest(canonicalBytes: bytes)

        #expect(decoded.formatVersion == SchemaManifest.currentFormatVersion)
        #expect(decoded.schema == schema)
        #expect(try decoded.canonicalBytes() == bytes)
        #expect(try decoded.fingerprint() == manifest.fingerprint())
    }

    @Test("plan and apply requests preserve the schema and concurrency guards")
    func requestsRoundTrip() throws {
        let manifest = SchemaManifest(schema: try makeSchema())
        let fingerprint = try manifest.fingerprint()
        let requests: [SchemaExecuteOperation.Request] = [
            .init(
                invocation: .plan(
                    manifest: manifest,
                    expectedFingerprint: nil
                )
            ),
            .init(
                invocation: .plan(
                    manifest: manifest,
                    expectedFingerprint: fingerprint
                )
            ),
            .init(
                invocation: .apply(
                    manifest: manifest,
                    expectedFingerprint: fingerprint,
                    idempotencyKey: "schema-apply-1"
                )
            ),
        ]

        for request in requests {
            let frame = try DatabaseWireEncoder().encodeRequest(
                DatabaseOperations.schemaExecute,
                requestID: 42,
                target: .database,
                request: request
            )
            let decoded = try DatabaseWireDecoder().decodeRequest(
                DatabaseOperations.schemaExecute,
                from: frame
            )
            #expect(decoded.requestID == 42)
            #expect(decoded.request == request)
        }
    }

    @Test("plan and applied responses preserve generation state")
    func responsesRoundTrip() throws {
        let fingerprint = try SchemaManifest(schema: makeSchema()).fingerprint()
        let responses: [SchemaExecuteOperation.Response] = [
            .plan(
                .init(
                    currentFingerprint: nil,
                    targetFingerprint: fingerprint,
                    compatibility: .initial,
                    issues: []
                )
            ),
            .applied(
                .init(
                    previousFingerprint: fingerprint,
                    fingerprint: fingerprint,
                    schemaVersion: .init(2, 1, 0),
                    generation: 7
                )
            ),
        ]

        for response in responses {
            let frame = try DatabaseWireEncoder().encodeResponse(
                DatabaseOperations.schemaExecute,
                requestID: 43,
                response: response
            )
            let decoded = try DatabaseWireDecoder().decodeResponse(
                DatabaseOperations.schemaExecute,
                from: frame,
                matching: 43
            )
            #expect(try decoded.get() == response)
        }
    }

    @Test("manifest rejects unknown versions and trailing data")
    func manifestRejectsNonCanonicalInput() throws {
        let encoded = try SchemaManifest(schema: makeSchema()).canonicalBytes()
        var unsupportedVersion = encoded.copyBytes()
        unsupportedVersion[0] = 2
        unsupportedVersion[1] = 0

        #expect(
            throws: DatabaseWireError.unsupportedSchemaManifestVersion(2)
        ) {
            _ = try SchemaManifest(
                canonicalBytes: ByteString(unsupportedVersion)
            )
        }

        var trailing = encoded.copyBytes()
        trailing.append(0)
        #expect(throws: DatabaseWireError.self) {
            _ = try SchemaManifest(canonicalBytes: ByteString(trailing))
        }
    }

    @Test("apply requires a non-empty idempotency key")
    func applyRejectsMissingIdempotencyKey() throws {
        let manifest = SchemaManifest(schema: try makeSchema())
        let request = SchemaExecuteOperation.Request(
            invocation: .apply(
                manifest: manifest,
                expectedFingerprint: try manifest.fingerprint(),
                idempotencyKey: ""
            )
        )

        #expect(
            throws: DatabaseWireError.invalidSchemaManifest(
                "Schema apply idempotency key must not be empty"
            )
        ) {
            _ = try DatabaseWireEncoder().encodeRequest(
                DatabaseOperations.schemaExecute,
                requestID: 44,
                target: .database,
                request: request
            )
        }
    }

    private func makeSchema() throws -> Schema {
        let venue = try Schema.Entity(
            name: "Venue",
            identifierType: .uuid,
            fields: [
                FieldSchema(name: "name", fieldNumber: 1, type: .string),
            ],
            ontology: .owlClass(
                iri: "urn:database:Venue",
                properties: [
                    OWLDataPropertyDescriptor(
                        name: "Venue_name",
                        fieldName: "name",
                        iri: "urn:database:name"
                    )
                ]
            )
        )
        let event = try Schema.Entity(
            name: "Event",
            identifierType: .composite([.string, .uint64]),
            fields: [
                FieldSchema(name: "tenant", fieldNumber: 1, type: .string),
                FieldSchema(name: "title", fieldNumber: 2, type: .string),
                FieldSchema(
                    name: "venue",
                    fieldNumber: 3,
                    type: .reference,
                    isOptional: true,
                    referenceTargetEntity: "Venue"
                ),
                FieldSchema(name: "state", fieldNumber: 4, type: .enum),
            ],
            directoryComponents: [
                .staticPath("events"),
                .dynamicField(fieldName: "tenant"),
            ],
            directoryLayer: .partition,
            indexes: [
                IndexDescriptorMetadata(
                    entityName: "Event",
                    name: "event_title",
                    kind: IndexKindMetadata(
                        identifier: "scalar",
                        subspaceStructure: .flat,
                        fields: [
                            .init(
                                identity: .init(name: "title", number: 2),
                                order: .ascending
                            ),
                        ],
                        metadata: ["collation": .string("binary")]
                    ),
                    commonOptions: .init(
                        unique: false,
                        sparse: true,
                        metadata: ["owner": "schema"]
                    ),
                    storedFieldNames: ["state"]
                ),
            ],
            relationships: [
                RelationshipDescriptor(
                    ownerTypeName: "Event",
                    propertyName: "venue",
                    propertyFieldNumber: 3,
                    relatedTypeName: "Venue",
                    cardinality: .optionalToOne,
                    deleteRule: .nullify
                ),
            ],
            fieldAccessRules: [
                FieldAccessRule(
                    field: .init(name: "title", number: 2),
                    read: .authenticated,
                    write: .roles(["editor"])
                ),
            ],
            enumMetadata: ["state": ["draft", "published"]],
            ontology: .owlClass(
                iri: "urn:database:Event",
                properties: [
                    OWLDataPropertyDescriptor(
                        name: "Event_title",
                        fieldName: "title",
                        iri: "urn:database:title"
                    )
                ]
            ),
            polymorphicMembership: PolymorphicMembership(
                identifier: "Content",
                directoryComponents: [.staticPath("content")],
                directoryLayer: .default,
                indexes: [
                    PolymorphicIndexDefinition(
                        name: "content_title",
                        definition: .scalar,
                        fields: [
                            PolymorphicIndexField(
                                name: "title",
                                order: .ascending
                            ),
                        ],
                        commonOptions: .init(),
                        storedFieldNames: ["state"]
                    ),
                ]
            )
        )
        return try Schema(
            entities: [event, venue],
            version: .init(2, 1, 0)
        )
    }
}
