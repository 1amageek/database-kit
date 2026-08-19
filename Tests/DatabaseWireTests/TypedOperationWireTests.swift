import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("Typed operation family wire")
struct TypedOperationWireTests {
    private var quad: RDFQuad {
        get throws {
            RDFQuad(
                subject: .iri(try RDFIRI("urn:event:1")),
                predicate: RDFPredicateIRI(
                    try RDFIRI("urn:calendar:startsAt")
                ),
                object: .literal(
                    RDFLiteral(
                        lexicalForm: "2026-07-16",
                        datatype: XSDDatatype.date.typedLiteralDatatype
                    )
                ),
                graph: RDFGraphName(
                    RDFSubject.iri(
                        try RDFIRI("urn:calendar:active")
                    )
                )
            )
        }
    }

    private let jobID = DatabaseTypes.UUID(
        high: 0x0011_2233_4455_6677,
        low: 0x8899_AABB_CCDD_EEFF
    )

    @Test("graph requests and responses round-trip by algorithm family")
    func graphFamilyRoundTrips() throws {
        let source = GraphAlgorithmOperation.Source(
            index: "eventGraph",
            partitions: try FieldObject([
                (key: "runID", value: .string("run-1")),
            ]),
            graph: .named(.identifier("urn:calendar:active")),
            edgeLabel: .identifier("related")
        )
        let invocations: [GraphAlgorithmOperation.Invocation] = [
            .shortestPath(
                source: .identifier("a"),
                target: .identifier("b"),
                maximumDepth: 10,
                bidirectional: true,
                maximumNodes: 1_000
            ),
            .weightedShortestPath(
                source: .identifier("a"),
                target: .identifier("b"),
                weightProperty: "cost",
                maximumWeight: 100,
                maximumNodes: 1_000
            ),
            .pageRank(
                dampingFactor: 0.85,
                maximumIterations: 100,
                convergenceThreshold: 0.000_001,
                personalizedSource: nil
            ),
            .community(
                maximumIterations: 50,
                computeModularity: true,
                minimumCommunitySize: 2,
                seed: 42
            ),
            .cycleDetection(maximumCycles: 10, maximumNodes: 1_000),
            .stronglyConnectedComponents(
                maximumComponents: 100,
                maximumNodes: 1_000
            ),
            .topologicalSort(maximumNodes: 1_000),
        ]
        for invocation in invocations {
            try expectRoundTrip(
                GraphAlgorithmOperation.Request(
                    source: source,
                    invocation: invocation,
                    page: .init(limit: 20, continuation: [1, 2])
                )
            )
        }

        try expectRoundTrip(
            GraphAlgorithmOperation.Request(
                source: .init(
                    index: "rdfDataset",
                    graph: .named(
                        .rdf(
                            .blankNode(
                                try RDFBlankNodeIdentifier(
                                    "calendar-graph"
                                )
                            )
                        )
                    ),
                    edgeLabel: .rdf(
                        .iri(try RDFIRI("urn:calendar:related"))
                    )
                ),
                invocation: .shortestPath(
                    source: .rdf(
                        .blankNode(
                            try RDFBlankNodeIdentifier("event")
                        )
                    ),
                    target: .rdf(
                        .iri(try RDFIRI("urn:event:target"))
                    ),
                    maximumDepth: 8,
                    bidirectional: true,
                    maximumNodes: 500
                )
            )
        )

        let responses: [GraphAlgorithmOperation.Response] = [
            .path(
                .init(
                    found: true,
                    nodes: [.identifier("a"), .identifier("b")],
                    edgeLabels: [.identifier("related")],
                    weights: [1],
                    totalWeight: 1,
                    nodesExplored: 2,
                    durationNanoseconds: 10,
                    progress: .complete
                )
            ),
            .ranking(
                .init(
                    scores: [.init(vertex: .identifier("a"), score: 0.75)],
                    iterations: 10,
                    convergenceDelta: 0.000_001,
                    progress: .complete
                )
            ),
            .communities(
                .init(
                    assignments: [
                        .init(
                            vertex: .identifier("a"),
                            community: .identifier("c1")
                        ),
                    ],
                    iterations: 5,
                    modularity: 0.4,
                    progress: .complete
                )
            ),
            .cycles(
                .init(
                    cycles: [
                        .init(terms: [
                            .identifier("a"),
                            .identifier("b"),
                            .identifier("a"),
                        ]),
                    ],
                    backEdges: [
                        .init(
                            source: .identifier("b"),
                            target: .identifier("a")
                        ),
                    ],
                    nodesExplored: 2,
                    progress: .complete
                )
            ),
            .components(
                .init(
                    components: [
                        .init(terms: [
                            .identifier("a"),
                            .identifier("b"),
                        ]),
                    ],
                    nodesExplored: 2,
                    progress: .complete
                )
            ),
            .topologicalOrder(
                .init(
                    order: [.identifier("a"), .identifier("b")],
                    cyclicNodes: [],
                    totalNodes: 2,
                    progress: .complete
                )
            ),
        ]
        for response in responses {
            try expectCanonicalRoundTrip(response)
        }
    }

    @Test("ontology requests and responses retain RDF structure")
    func ontologyFamilyRoundTrips() throws {
        let document = OntologyExecuteOperation.Document(
            ontology: "urn:calendar:ontology",
            imports: ["urn:time"],
            axioms: [try quad]
        )
        let invocations: [OntologyExecuteOperation.Invocation] = [
            .describe(ontology: document.ontology),
            .upsert(document: document, expectedRevision: 4),
            .delete(ontology: document.ontology, expectedRevision: 5),
            .reason(ontology: document.ontology, profile: .owlRL),
            .hierarchy(
                ontology: document.ontology,
                resource: "urn:calendar:Event",
                resourceKind: .class,
                direction: .ancestors,
                maximumDepth: 8
            ),
            .validateSchema(ontology: document.ontology),
        ]
        for invocation in invocations {
            try expectRoundTrip(OntologyExecuteOperation.Request(invocation: invocation))
        }

        try expectCanonicalRoundTrip(
            OntologyExecuteOperation.Response.document(
                .init(
                    ontology: document.ontology,
                    revision: 5,
                    imports: document.imports,
                    axioms: document.axioms
                )
            )
        )
        try expectCanonicalRoundTrip(
            OntologyExecuteOperation.Response.mutation(
                .init(commitVersion: 10, revision: 6)
            )
        )
        try expectCanonicalRoundTrip(
            OntologyExecuteOperation.Response.inference(
                .init(inferredAxioms: [try quad], isComplete: true)
            )
        )
        try expectCanonicalRoundTrip(
            OntologyExecuteOperation.Response.hierarchy(
                .init(entries: [.init(resource: "urn:Thing", depth: 1)])
            )
        )
        try expectCanonicalRoundTrip(
            OntologyExecuteOperation.Response.validation(
                try validationReport()
            )
        )
    }

    @Test("SHACL requests and responses retain data and focus selections")
    func shaclFamilyRoundTrips() throws {
        let identity = try EntityReference(
            entity: "Event",
            id: .string("event-1")
        )
        let invocations: [SHACLExecuteOperation.Invocation] = [
            .describeShapes(graph: "urn:calendar:shapes"),
            .upsertShapes(
                graph: "urn:calendar:shapes",
                shapes: [try quad],
                expectedRevision: 2
            ),
            .deleteShapes(graph: "urn:calendar:shapes", expectedRevision: 3),
            .validate(
                shapesGraph: "urn:calendar:shapes",
                data: .init(
                    entity: "Event",
                    index: "calendarGraph",
                    graph: .defaultGraph
                ),
                focus: .entities([identity]),
                entailment: .owl(ontology: "urn:calendar:ontology")
            ),
            .validate(
                shapesGraph: "urn:calendar:shapes",
                data: .init(
                    entity: "Event",
                    index: "calendarGraph",
                    partitions: try FieldObject([
                        (key: "runID", value: .string("run-1")),
                    ]),
                    graph: .named(
                        .iri(try RDFIRI("urn:calendar:active"))
                    )
                ),
                focus: .nodes([
                    .iri(try RDFIRI("urn:event:1")),
                ]),
                entailment: .rdfs
            ),
        ]
        for invocation in invocations {
            try expectRoundTrip(SHACLExecuteOperation.Request(invocation: invocation))
        }
        try expectCanonicalRoundTrip(
            SHACLExecuteOperation.Response.shapes(
                .init(
                    graph: "urn:calendar:shapes",
                    revision: 3,
                    shapes: [try quad]
                )
            )
        )
        try expectCanonicalRoundTrip(
            SHACLExecuteOperation.Response.validation(
                try validationReport()
            )
        )
    }

    @Test("command and maintenance payloads are statically shaped")
    func commandAndMaintenanceRoundTrip() throws {
        try expectRoundTrip(
            CommandRequest(
                command: CommandDeclaration(
                    identifier: try CommandIdentifier(
                        "calendar.activateImport"
                    ),
                    access: .readWrite
                ),
                input: try FieldObject([
                    (key: "runID", value: .string("run-1")),
                ])
            )
        )
        try expectRoundTrip(
            CommandExecuteOperation.Response.read(
                output: .bool(true),
                continuation: [2]
            )
        )
        try expectRoundTrip(
            CommandExecuteOperation.Response.write(
                output: .uint64(1),
                commitVersion: 42,
                continuation: nil
            )
        )

        let invocations: [MaintenanceExecuteOperation.Invocation] = [
            .migrationStatus,
            .runMigrations(targetVersion: .init(4, 0, 0)),
            .indexStatus(
                entity: "Event",
                index: nil,
                partitions: try FieldObject([
                    (key: "runID", value: .string("run-1")),
                ])
            ),
            .rebuildIndex(
                entity: "Event",
                index: "startsAt",
                partitions: try FieldObject([
                    (key: "runID", value: .string("run-1")),
                ]),
                batchSize: 500
            ),
            .compact,
        ]
        for invocation in invocations {
            try expectRoundTrip(
                MaintenanceExecuteOperation.Request(invocation: invocation)
            )
        }
        try expectCanonicalRoundTrip(
            MaintenanceExecuteOperation.Response.migrationStatus(
                .init(
                    currentVersion: .init(3, 0, 0),
                    targetVersion: .init(4, 0, 0),
                    pendingMigrationIdentifiers: ["calendar-v4"]
                )
            )
        )
        try expectCanonicalRoundTrip(
            MaintenanceExecuteOperation.Response.migrationStatus(
                .init(
                    currentVersion: nil,
                    targetVersion: .init(1, 0, 0),
                    pendingMigrationIdentifiers: ["initial-schema"]
                )
            )
        )
        try expectCanonicalRoundTrip(
            MaintenanceExecuteOperation.Response.indexStatus(
                .init(
                    indexes: [
                        .init(
                            entity: "Event",
                            index: "startsAt",
                            partitions: try FieldObject([
                                (
                                    key: "runID",
                                    value: .string("run-1")
                                ),
                            ]),
                            state: .ready,
                            indexedEntityCount: 10
                        ),
                    ]
                )
            )
        )
    }

    @Test("command descriptors bind semantic input and output to the fixed operation")
    func commandDescriptorBindsCanonicalPayloads() throws {
        let declaration = CommandDeclaration(
            identifier: try CommandIdentifier("calendar.activateImport"),
            access: .readWrite
        )
        let input = try FieldObject([
            (key: "expectedRevision", value: .uint64(7)),
            (key: "runID", value: .string("run-1")),
        ])
        let output = FieldValue.object(
            try FieldObject([
                (key: "activated", value: .bool(true)),
                (key: "importedCount", value: .uint64(128)),
            ])
        )
        let budget = ExecutionBudget(
            maximumRows: 512,
            maximumWorkUnits: 4_096,
            maximumIntermediateRows: 256,
            maximumIntermediateBytes: 1_048_576,
            timeoutMilliseconds: 2_000,
        )
        try expectRoundTrip(budget)
        let request = CommandRequest(
            command: declaration,
            input: input,
            budget: budget
        )
        let requestPayload = try DatabaseOperationCatalog.commandExecute
            .encodeRequestPayload(request)
        #expect(
            try DatabaseOperationCatalog.commandExecute.decodeRequestPayload(
                requestPayload
            ) == request
        )

        let requestFrame = try DatabaseOperationCatalog.commandExecute
            .encodeTestDatabaseRequest(
            requestID: 17,
            metadata: .init(traceID: "command"),
            request: request
        )
        let requestEnvelope = try EnvelopeWireFormat.decodeRequest(
            requestFrame
        )
        #expect(
            try DatabaseOperationCatalog.commandExecute.decodeRequest(
                requestEnvelope
            ) == request
        )

        let response = CommandExecuteOperation.Response.write(
            output: output,
            commitVersion: 42,
            continuation: [3, 2, 1]
        )
        let responseFrame = try DatabaseOperationCatalog.commandExecute
            .encodeResponse(
                requestID: 17,
                response: response
            )
        #expect(
            try DatabaseOperationCatalog.commandExecute.decodeResponse(
                responseFrame,
                matching: 17
            ) == .success(response)
        )

        let readResponse = CommandExecuteOperation.Response.read(
            output: output,
            continuation: [1, 2, 3]
        )
        #expect(
            try DatabaseOperationCatalog.commandExecute.decodeResponsePayload(
                DatabaseOperationCatalog.commandExecute.encodeResponsePayload(
                    readResponse
                )
            ) == readResponse
        )
    }

    @Test("command access and identifiers are validated at both wire boundaries")
    func commandContractValidationIsStrict() throws {
        #expect(
            throws: DatabaseWireError.invalidCommandAccess(2)
        ) {
            try EnvelopeWireFormat.decode(
                CommandAccess.self,
                from: [2]
            )
        }

        let oversizedIdentifier = String(
            repeating: "a",
            count: CommandIdentifier.maximumUTF8Bytes + 1
        )
        #expect(
            throws: CommandIdentifierError.tooLong(
                actualUTF8Bytes: oversizedIdentifier.utf8.count,
                maximumUTF8Bytes: CommandIdentifier.maximumUTF8Bytes
            )
        ) {
            try CommandIdentifier(oversizedIdentifier)
        }

        let emptyIdentifierRequest = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writer.writeString("")
            try CommandAccess.readOnly.encode(into: &writer)
            try FieldObject().encode(into: &writer)
            try ExecutionBudget().encode(into: &writer)
        }
        #expect(
            throws: DatabaseWireError.invalidCommandIdentifier(.empty)
        ) {
            try EnvelopeWireFormat.decode(
                CommandRequest.self,
                from: emptyIdentifierRequest
            )
        }
    }

    @Test("durable job lifecycle uses canonical identifiers and outcomes")
    func jobFamilyRoundTrips() throws {
        let jobOperation = JobOperations.maintenance.identifier
        let job = makeTestJobIdentity(
            jobID: jobID,
            operation: jobOperation
        )
        let responseDigest = try JobResultDigest(
            [UInt8](repeating: 0xaa, count: JobResultDigest.byteCount)
        )
        let firstContinuation = try JobResultOperation.Continuation(
            job: job,
            responseDigest: responseDigest,
            nextChunkIndex: 1
        )
        try expectRoundTrip(
            makeTestJobStartRequest(
                operation: jobOperation,
                requestPayload: [1, 2, 3],
                maximumSliceWorkUnits: 100,
                retryPolicy: .init(
                    maximumAttempts: 4,
                    initialBackoffMilliseconds: 250,
                    maximumBackoffMilliseconds: 5_000
                )
            )
        )
        try expectRoundTrip(
            makeTestJobStartResponse(
                jobID: jobID,
                operation: jobOperation
            )
        )
        try expectRoundTrip(JobStatusOperation.Request(job: job))
        try expectRoundTrip(
            JobResultOperation.Request(
                job: job,
                continuation: firstContinuation
            )
        )
        try expectRoundTrip(
            try JobStatusOperation.Response(
                state: .committingUnsuccessfulOutcome,
                job: job,
                completedWorkUnits: 50,
                totalWorkUnits: 100,
                executionCount: 7,
                currentSliceAttempt: 2,
                unsuccessfulOutcomeCommitAttempt: 3,
                lastUnsuccessfulOutcomeCommitError: RemoteOperationError(
                    category: .internalFailure,
                    code: "JOB_UNSUCCESSFUL_OUTCOME_COMMIT_FAILED",
                    message: "Unsuccessful outcome commit will be retried",
                    retryability: .backoff
                ),
                nextAttemptAt: .init(secondsSinceUnixEpoch: 1_784_131_100),
                updatedAt: .init(secondsSinceUnixEpoch: 1_784_131_000)
            )
        )
        try expectRoundTrip(
            JobResultOperation.Response.succeeded(
                job: job,
                responsePayloadPage: [4, 5],
                totalResponseBytes: 8,
                responseDigest: responseDigest,
                continuation: try JobResultOperation.Continuation(
                    job: job,
                    responseDigest: responseDigest,
                    nextChunkIndex: 2
                )
            )
        )
        try expectRoundTrip(
            JobResultOperation.Response.failed(
                job: job,
                error: .init(
                    category: .resourceLimit,
                    code: "WORK_LIMIT",
                    message: "Work limit reached",
                    retryability: .backoff
                )
            )
        )
        try expectRoundTrip(
            JobResultOperation.Response.cancelled(job: job)
        )
        try expectRoundTrip(JobCancelOperation.Request(job: job))
        try expectRoundTrip(
            try JobCancelOperation.Response(
                job: job,
                state: .committingUnsuccessfulOutcome,
                accepted: true
            )
        )
    }

    @Test("job status rejects impossible state combinations")
    func jobStatusRejectsImpossibleCombinations() throws {
        let operation = try JobOperationIdentifier(
            family: .maintenanceExecute,
            kind: "database.test.status"
        )
        let job = makeTestJobIdentity(
            jobID: jobID,
            operation: operation
        )
        let now = Timestamp(
            secondsSinceUnixEpoch: 1_784_131_200
        )
        let past = Timestamp(
            secondsSinceUnixEpoch: 1_784_131_199
        )
        #expect(throws: DatabaseWireError.invalidJobStatus) {
            try JobStatusOperation.Response(
                state: .pending,
                job: job,
                completedWorkUnits: 0,
                executionCount: 0,
                currentSliceAttempt: 0,
                updatedAt: now
            )
        }
        #expect(throws: DatabaseWireError.invalidJobStatus) {
            try JobStatusOperation.Response(
                state: .running,
                job: job,
                completedWorkUnits: 0,
                executionCount: 1,
                currentSliceAttempt: 0,
                updatedAt: now
            )
        }
        #expect(throws: DatabaseWireError.invalidJobStatus) {
            try JobStatusOperation.Response(
                state: .committingUnsuccessfulOutcome,
                job: job,
                completedWorkUnits: 1,
                executionCount: 1,
                currentSliceAttempt: 1,
                unsuccessfulOutcomeCommitAttempt: 0,
                updatedAt: now
            )
        }
        #expect(throws: DatabaseWireError.invalidJobStatus) {
            try JobStatusOperation.Response(
                state: .failed,
                job: job,
                completedWorkUnits: 1,
                executionCount: 1,
                currentSliceAttempt: 1,
                unsuccessfulOutcomeCommitAttempt: 0,
                updatedAt: now
            )
        }
        #expect(throws: DatabaseWireError.invalidJobStatus) {
            try JobStatusOperation.Response(
                state: .succeeded,
                job: job,
                completedWorkUnits: 2,
                totalWorkUnits: 1,
                executionCount: 1,
                currentSliceAttempt: 1,
                updatedAt: now
            )
        }
        #expect(throws: DatabaseWireError.invalidJobStatus) {
            try JobStatusOperation.Response(
                state: .pending,
                job: job,
                completedWorkUnits: 0,
                executionCount: 0,
                currentSliceAttempt: 0,
                nextAttemptAt: past,
                updatedAt: now
            )
        }

        let pending = try JobStatusOperation.Response(
            state: .pending,
            job: job,
            completedWorkUnits: 0,
            executionCount: 0,
            currentSliceAttempt: 0,
            nextAttemptAt: now,
            updatedAt: now
        )
        var invalidBytes = [UInt8](
            try EnvelopeWireFormat.encode(pending)
        )
        invalidBytes[0] = JobStatusOperation.State.failed.rawValue
        #expect(throws: DatabaseWireError.invalidJobStatus) {
            try EnvelopeWireFormat.decode(
                JobStatusOperation.Response.self,
                from: ByteString(invalidBytes)
            )
        }
    }

    @Test("job cancellation rejects impossible response combinations")
    func jobCancellationRejectsImpossibleCombinations() throws {
        let operation = try JobOperationIdentifier(
            family: .maintenanceExecute,
            kind: "database.test.cancel"
        )
        let job = makeTestJobIdentity(
            jobID: jobID,
            operation: operation
        )

        #expect(throws: DatabaseWireError.invalidJobCancellationResponse) {
            try JobCancelOperation.Response(
                job: job,
                state: .cancelled,
                accepted: true
            )
        }
        #expect(throws: DatabaseWireError.invalidJobCancellationResponse) {
            try JobCancelOperation.Response(
                job: job,
                state: .pending,
                accepted: false
            )
        }

        let invalidWire = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter)
                throws(DatabaseWireError) -> Void in
            try job.encode(into: &writer)
            writer.writeUInt8(JobStatusOperation.State.failed.rawValue)
            writer.writeBool(true)
        }
        #expect(throws: DatabaseWireError.invalidJobCancellationResponse) {
            try EnvelopeWireFormat.decode(
                JobCancelOperation.Response.self,
                from: invalidWire
            )
        }
    }

    @Test("capabilities advertise a canonical exact job operation set")
    func capabilitiesAdvertiseCanonicalJobOperations() throws {
        let command = try JobOperationIdentifier(
            family: .commandExecute,
            kind: "calendar.import.validate"
        )
        let maintenance = JobOperations.maintenance.identifier
        let response = CapabilitiesDescribeOperation.Response(
            runtimeVersion: "1",
            features: [],
            jobOperations: [command, maintenance]
        )
        try expectRoundTrip(response)

        let reversed = CapabilitiesDescribeOperation.Response(
            runtimeVersion: "1",
            features: [],
            jobOperations: [maintenance, command]
        )
        #expect(throws: DatabaseWireError.nonCanonicalJobOperationSet) {
            try EnvelopeWireFormat.encode(reversed)
        }

        let duplicate = CapabilitiesDescribeOperation.Response(
            runtimeVersion: "1",
            features: [],
            jobOperations: [command, command]
        )
        #expect(throws: DatabaseWireError.nonCanonicalJobOperationSet) {
            try EnvelopeWireFormat.encode(duplicate)
        }

        let nonCanonicalWire = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter)
                throws(DatabaseWireError) in
            try writer.writeString("1")
            try writer.writeCount(0)
            try writer.writeCount(2)
            try maintenance.encode(into: &writer)
            try command.encode(into: &writer)
        }
        #expect(throws: DatabaseWireError.nonCanonicalJobOperationSet) {
            try EnvelopeWireFormat.decode(
                CapabilitiesDescribeOperation.Response.self,
                from: nonCanonicalWire
            )
        }
    }

    @Test("job result enforces digest, page, and continuation limits")
    func jobResultEnforcesFieldLimits() throws {
        let jobOperation = JobOperations.maintenance.identifier
        let job = makeTestJobIdentity(
            jobID: jobID,
            operation: jobOperation
        )
        #expect(
            throws: DatabaseWireError.invalidDigestLength(
                actual: JobResultDigest.byteCount - 1,
                expected: JobResultDigest.byteCount
            )
        ) {
            try JobResultDigest(
                [UInt8](
                    repeating: 0,
                    count: JobResultDigest.byteCount - 1
                )
            )
        }
        let digest = try JobResultDigest(
            [UInt8](repeating: 0, count: JobResultDigest.byteCount)
        )
        #expect(throws: DatabaseWireError.invalidResultPayload(0)) {
            try JobResultOperation.Continuation(
                job: job,
                responseDigest: digest,
                nextChunkIndex: 0
            )
        }
        let oversized = JobResultOperation.Response.succeeded(
            job: job,
            responsePayloadPage: ByteString(
                [UInt8](
                    repeating: 0,
                    count: JobResultOperation.maximumResponsePageBytes + 1
                )
            ),
            totalResponseBytes: UInt64(
                JobResultOperation.maximumResponsePageBytes + 1
            ),
            responseDigest: digest,
            continuation: nil
        )
        #expect(
            throws: DatabaseWireError.byteStringTooLarge(
                actual: JobResultOperation.maximumResponsePageBytes + 1,
                maximum: JobResultOperation.maximumResponsePageBytes
            )
        ) {
            try EnvelopeWireFormat.encode(oversized)
        }
    }

    @Test("job result digest is canonical across page boundaries")
    func jobResultDigestIsCanonicalAcrossPageBoundaries() throws {
        var accumulator = makeTestJobResultDigestAccumulator(
            operation: JobOperations.maintenance.identifier
        )
        accumulator.update([0x01, 0x02])
        accumulator.update([0x03, 0x04, 0x05])

        #if DATABASE_KIT_MULTI_BASE
        let expected: [UInt8] = [
            0x65, 0xfc, 0x3a, 0x41, 0xe7, 0x47, 0x9e, 0x2b,
            0x9c, 0xa3, 0x2b, 0x1a, 0x9f, 0x2f, 0xb3, 0xca,
            0x1d, 0x5e, 0x5f, 0x79, 0xc9, 0x61, 0xfe, 0x24,
            0xd9, 0x0f, 0x26, 0x2d, 0xdd, 0x6c, 0x69, 0x97,
        ]
        #else
        let expected: [UInt8] = [
            0xd7, 0x67, 0x5e, 0x66, 0x99, 0xfa, 0x0c, 0x28,
            0x69, 0x8a, 0x17, 0x04, 0x80, 0x12, 0x42, 0xbc,
            0x89, 0xe2, 0x54, 0xd5, 0xae, 0x45, 0xc6, 0x69,
            0x6d, 0xd0, 0xef, 0xd3, 0x55, 0x7a, 0x83, 0x34,
        ]
        #endif
        #expect(accumulator.finalize().bytes.copyBytes() == expected)
    }

    @Test("job result digest matches a multi-block golden vector")
    func jobResultDigestMatchesMultiBlockGoldenVector() throws {
        let payload = ByteString(
            (0..<1_000).map { UInt8(truncatingIfNeeded: $0) }
        )
        var accumulator = makeTestJobResultDigestAccumulator(
            operation: JobOperations.maintenance.identifier
        )
        accumulator.update(payload[0..<63])
        accumulator.update(payload[63..<511])
        accumulator.update(payload[511..<1_000])

        #if DATABASE_KIT_MULTI_BASE
        let expected: [UInt8] = [
            0x05, 0x52, 0xa1, 0x22, 0xbb, 0xfc, 0x43, 0xdd,
            0xcc, 0x1b, 0xf5, 0x01, 0x7b, 0xba, 0x70, 0x4f,
            0x5c, 0x67, 0x69, 0xf4, 0xfe, 0x3d, 0x73, 0x0a,
            0x76, 0xf9, 0x5d, 0x11, 0xd2, 0xfb, 0x64, 0xca,
        ]
        #else
        let expected: [UInt8] = [
            0x53, 0x21, 0x1c, 0x8f, 0x6b, 0x47, 0x20, 0x81,
            0x9b, 0xd0, 0x0b, 0xb8, 0x82, 0x01, 0x4e, 0x0b,
            0xc2, 0xe1, 0x18, 0xb9, 0x51, 0xf7, 0x0a, 0xd6,
            0x26, 0x5c, 0x28, 0xe6, 0x09, 0x13, 0xf5, 0xc6,
        ]
        #endif
        #expect(accumulator.finalize().bytes.copyBytes() == expected)
    }

    @Test("job operation identifiers enforce their canonical bounded grammar")
    func jobOperationIdentifierValidationIsStrict() throws {
        let valid = try JobOperationIdentifier(
            family: .commandExecute,
            kind: "calendar.import.validate"
        )
        try expectRoundTrip(valid)

        #expect(throws: DatabaseWireError.invalidJobOperationKind) {
            try JobOperationIdentifier(
                family: .commandExecute,
                kind: "Calendar.Import.Validate"
            )
        }
        #expect(throws: DatabaseWireError.invalidJobOperationKind) {
            try JobOperationIdentifier(
                family: .commandExecute,
                kind: "calendar..validate"
            )
        }
        #expect(
            throws: DatabaseWireError.invalidJobOperationFamily(
                DatabaseOperationIdentifier.jobStart.rawValue
            )
        ) {
            try JobOperationIdentifier(
                family: .jobStart,
                kind: "calendar.import.validate"
            )
        }

        let oversizedKind = String(
            repeating: "a",
            count: JobOperationIdentifier.maximumKindUTF8Bytes + 1
        )
        let encoded = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter)
                throws(DatabaseWireError) in
            DatabaseOperationIdentifier.commandExecute.encode(into: &writer)
            try writer.writeString(oversizedKind)
        }
        #expect(
            throws: DatabaseWireError.stringTooLarge(
                actual: oversizedKind.utf8.count,
                maximum: JobOperationIdentifier.maximumKindUTF8Bytes
            )
        ) {
            try EnvelopeWireFormat.decode(
                JobOperationIdentifier.self,
                from: encoded
            )
        }
    }

    @Test("job result binding includes job identity and operation kind")
    func jobResultBindingIsStrict() throws {
        let maintenance = JobOperations.maintenance.identifier
        let calendar = try JobOperationIdentifier(
            family: .maintenanceExecute,
            kind: "calendar.import.validate"
        )
        var maintenanceDigest = makeTestJobResultDigestAccumulator(
            operation: maintenance
        )
        maintenanceDigest.update([1, 2, 3])
        var calendarDigest = makeTestJobResultDigestAccumulator(
            operation: calendar
        )
        calendarDigest.update([1, 2, 3])
        #expect(maintenanceDigest.finalize() != calendarDigest.finalize())

        let digest = try JobResultDigest(
            [UInt8](repeating: 0, count: JobResultDigest.byteCount)
        )
        let expectedJob = makeTestJobIdentity(
            jobID: jobID,
            operation: maintenance
        )
        let otherJob = makeTestJobIdentity(
            jobID: DatabaseTypes.UUID(high: jobID.high ^ 1, low: jobID.low),
            operation: maintenance
        )
        let continuation = try JobResultOperation.Continuation(
            job: otherJob,
            responseDigest: digest,
            nextChunkIndex: 1
        )
        #expect(throws: DatabaseWireError.invalidResultPayload(2)) {
            try EnvelopeWireFormat.encode(
                JobResultOperation.Request(
                    job: expectedJob,
                    continuation: continuation
                )
            )
        }
        #expect(throws: DatabaseWireError.invalidResultPayload(1)) {
            try EnvelopeWireFormat.encode(
                JobResultOperation.Response.succeeded(
                    job: expectedJob,
                    responsePayloadPage: [1],
                    totalResponseBytes: 2,
                    responseDigest: digest,
                    continuation: continuation
                )
            )
        }
    }

    @Test("typed job start binds the canonical maintenance request payload")
    func typedJobStartUsesTheCanonicalWireLayout() throws {
        let request = MaintenanceExecuteOperation.Request(invocation: .compact)
        let retryPolicy = JobStartOperation.RetryPolicy(
            maximumAttempts: 2,
            initialBackoffMilliseconds: 10,
            maximumBackoffMilliseconds: 20
        )
        let start = try makeTestJobOperationStartRequest(
            JobOperations.maintenance,
            request: request,
            maximumSliceWorkUnits: 77,
            retryPolicy: retryPolicy
        )
        let typedFrame = try DatabaseOperationCatalog.jobStart
            .encodeTestDatabaseRequest(
            requestID: 91,
            metadata: OperationRequestMetadata(traceID: "declared-job"),
            request: start
        )

        let canonicalFrame = try DatabaseOperationCatalog.jobStart
            .encodeTestDatabaseRequest(
            requestID: 91,
            metadata: OperationRequestMetadata(traceID: "declared-job"),
            request: makeTestJobStartRequest(
                operation: JobOperations.maintenance.identifier,
                requestPayload: try DatabaseOperationCatalog.maintenanceExecute
                    .encodeRequestPayload(request),
                maximumSliceWorkUnits: 77,
                retryPolicy: retryPolicy
            )
        )

        #expect(typedFrame == canonicalFrame)
        let envelope = try EnvelopeWireFormat.decodeRequest(typedFrame)
        let rawRequest = try DatabaseOperationCatalog.jobStart.decodeRequest(
            envelope
        )
        #expect(
            try JobOperations.maintenance.decodeStartRequest(
                rawRequest.requestPayload
            ) == request
        )
        let completedResponse = MaintenanceExecuteOperation.Response.execution(
            .init(kind: .compaction, completedWorkUnits: 77, isComplete: true)
        )
        let completedPayload = try JobOperations.maintenance
            .encodeCompletedResponse(completedResponse)
        let decodedResponse = try JobOperations.maintenance
            .decodeCompletedResponse(completedPayload)
        guard case .execution(let decodedResult) = decodedResponse else {
            Issue.record("Expected an execution response")
            return
        }
        #expect(decodedResult.kind == .compaction)
        #expect(decodedResult.completedWorkUnits == 77)
        #expect(decodedResult.isComplete)
        #expect(
            JobOperations.maintenance.identifier
                == (try DatabaseOperationCatalog.maintenanceExecute.resumableJob(
                    kind: "database.maintenance"
                )).identifier
        )
    }

    private func validationReport() throws -> ValidationReport {
        .init(
            conforms: false,
            issues: [
                .init(
                    severity: .violation,
                    code: "MIN_COUNT",
                    messages: ["Required value is missing"],
                    focusNode: .iri(try RDFIRI("urn:event:1")),
                    path: .sequence(
                        try SHACLPathList([
                            .predicate(
                                try RDFPredicateIRI("urn:calendar:venue")
                            ),
                            .alternative(
                                try SHACLPathList([
                                    .predicate(
                                        try RDFPredicateIRI(
                                            "urn:calendar:name"
                                        )
                                    ),
                                    .inverse(
                                        .predicate(
                                            try RDFPredicateIRI(
                                                "urn:calendar:labelFor"
                                            )
                                        )
                                    ),
                                ])
                            ),
                        ])
                    ),
                    value: .literal(
                        .init(
                            lexicalForm: "",
                            datatype: XSDDatatype.string
                                .typedLiteralDatatype
                        )
                    ),
                    sourceConstraintComponent: "http://www.w3.org/ns/shacl#MinCountConstraintComponent",
                    sourceShape: .blankNode(
                        try RDFBlankNodeIdentifier("event-shape")
                    )
                ),
            ]
        )
    }

    private func expectRoundTrip<Value>(
        _ value: Value
    ) throws where Value: WireValue & Equatable {
        let encoded = try EnvelopeWireFormat.encode(value)
        #expect(try EnvelopeWireFormat.decode(Value.self, from: encoded) == value)
    }

    private func expectCanonicalRoundTrip<Value>(
        _ value: Value
    ) throws where Value: WireValue {
        let encoded = try EnvelopeWireFormat.encode(value)
        let decoded = try EnvelopeWireFormat.decode(Value.self, from: encoded)
        #expect(try EnvelopeWireFormat.encode(decoded) == encoded)
    }
}
