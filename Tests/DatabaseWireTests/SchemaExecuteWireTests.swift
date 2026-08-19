import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
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
                0x02, 0x00,
                0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00,
            ])
        )
        #expect(
            try emptyManifest.fingerprint().bytes == ByteString([
                0x38, 0x92, 0xa8, 0x8a, 0x1c, 0x45, 0x4d, 0x52,
                0xa2, 0x38, 0x34, 0x73, 0xb4, 0x82, 0x7c, 0xbf,
                0xdb, 0x11, 0x00, 0xef, 0x18, 0x14, 0x97, 0x81,
                0x60, 0x9c, 0x48, 0x51, 0xae, 0x54, 0xc0, 0xa5,
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

        let zeroByteLimits = try DatabaseWireLimits(
            maximumFrameBytes: 0,
            maximumStringBytes: 0,
            maximumByteStringBytes: 0,
            maximumCollectionCount: 0,
            maximumNestingDepth: 0,
            maximumObjectCount: 0
        )
        #expect(throws: SchemaFingerprintError.canonicalRepresentationUnavailable) {
            _ = try emptyManifest.fingerprint(limits: zeroByteLimits)
        }
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
            #if DATABASE_KIT_MULTI_BASE
            let frame = try DatabaseWireEncoder().encodeRequest(
                DatabaseOperationCatalog.schemaExecute,
                requestID: 42,
                target: .database,
                request: request
            )
            #else
            let frame = try DatabaseWireEncoder().encodeRequest(
                DatabaseOperationCatalog.schemaExecute,
                requestID: 42,
                request: request
            )
            #endif
            let decoded = try DatabaseWireDecoder().decodeRequest(
                DatabaseOperationCatalog.schemaExecute,
                from: frame
            )
            #expect(decoded.requestID == 42)
            #expect(decoded.request == request)
        }
    }

    @Test("plan, accepted, and applied responses preserve state")
    func responsesRoundTrip() throws {
        let fingerprint = try SchemaManifest(schema: makeSchema()).fingerprint()
        #if DATABASE_KIT_MULTI_BASE
        let job = JobIdentity(
            jobID: DatabaseTypes.UUID(
                high: 0x0011_2233_4455_6677,
                low: 0x8899_AABB_CCDD_EEFF
            ),
            operation: try DatabaseOperationCatalog.schemaExecute
                .resumableJob(kind: "database.schema-apply")
                .identifier,
            target: .database
        )
        #else
        let job = JobIdentity(
            jobID: DatabaseTypes.UUID(
                high: 0x0011_2233_4455_6677,
                low: 0x8899_AABB_CCDD_EEFF
            ),
            operation: try DatabaseOperationCatalog.schemaExecute
                .resumableJob(kind: "database.schema-apply")
                .identifier
        )
        #endif
        let responses: [SchemaExecuteOperation.Response] = [
            .plan(
                .init(
                    currentFingerprint: nil,
                    targetFingerprint: fingerprint,
                    compatibility: .initial,
                    issues: []
                )
            ),
            .accepted(job),
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
                DatabaseOperationCatalog.schemaExecute,
                requestID: 43,
                response: response
            )
            let decoded = try DatabaseWireDecoder().decodeResponse(
                DatabaseOperationCatalog.schemaExecute,
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
        let unsupportedFormatVersion = SchemaManifest.currentFormatVersion + 1
        unsupportedVersion[0] = UInt8(truncatingIfNeeded: unsupportedFormatVersion)
        unsupportedVersion[1] = UInt8(
            truncatingIfNeeded: unsupportedFormatVersion >> 8
        )

        #expect(
            throws: DatabaseWireError.unsupportedSchemaManifestVersion(
                unsupportedFormatVersion
            )
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

    @Test("Manifest rejects duplicate field identities before index construction")
    func manifestRejectsDuplicateFieldIdentity() throws {
        let bytes = try DatabaseWireWriter.encode {
            writer throws(DatabaseWireError) in
            writer.writeUInt16(SchemaManifest.currentFormatVersion)
            writer.writeUInt32(1)
            writer.writeUInt32(0)
            writer.writeUInt32(0)
            try writer.writeCount(1)

            try writer.writeString("Entry")
            writer.writeUInt8(9)
            try writer.writeCount(2)
            for _ in 0..<2 {
                try writer.writeString("value")
                writer.writeInt64(1)
                try writer.writeString(FieldSchemaType.string.rawValue)
                writer.writeBool(false)
                writer.writeBool(false)
                writer.writeBool(false)
            }
            try writer.writeCount(0)
            try writer.writeString(DirectoryLayer.default.rawValue)
            try writer.writeCount(1)
            try writer.writeString("Entry")
            try writer.writeString("Entry_value")
            writer.writeUInt8(0)
            try writer.writeCount(1)
            try writer.writeString("value")
            writer.writeInt64(1)
            writer.writeUInt8(0)
            try writer.writeCount(0)
            writer.writeBool(false)
            try writer.writeCount(0)
            try writer.writeCount(0)
            try writer.writeCount(0)
            writer.writeUInt8(0)
            writer.writeBool(false)
        }

        #expect(throws: DatabaseWireError.self) {
            _ = try SchemaManifest(canonicalBytes: bytes)
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
            #if DATABASE_KIT_MULTI_BASE
            _ = try DatabaseWireEncoder().encodeRequest(
                DatabaseOperationCatalog.schemaExecute,
                requestID: 44,
                target: .database,
                request: request
            )
            #else
            _ = try DatabaseWireEncoder().encodeRequest(
                DatabaseOperationCatalog.schemaExecute,
                requestID: 44,
                request: request
            )
            #endif
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
        let eventFields = [
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
        ]
        let eventIndex = try IndexDescriptor(
            entityName: "Event",
            declaration: .ordered(
                name: "event_title",
                keys: [.ascending(.init(name: "title", number: 2))],
                includedFields: [.init(name: "state", number: 4)]
            ),
            fieldSchemas: eventFields
        )
        let event = try Schema.Entity(
            name: "Event",
            identifierType: .composite([.string, .uint64]),
            fields: eventFields,
            directoryComponents: [
                .staticPath("events"),
                .dynamicField(fieldName: "tenant"),
            ],
            directoryLayer: .partition,
            indexes: [eventIndex],
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
                    .ordered(
                        name: "content_title",
                        keys: [.ascending("title")],
                        includedFields: ["state"]
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
