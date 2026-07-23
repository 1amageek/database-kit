import DatabaseValue
import DatabaseWire
import Testing

@Suite("Typed operation family wire")
struct TypedOperationWireTests {
    private var quad: DatabaseRDFQuad {
        get throws {
            try DatabaseRDFQuad(
                subject: .iri("urn:event:1"),
                predicate: .iri("urn:calendar:startsAt"),
                object: .literal(
                    DatabaseRDFLiteral(
                        lexicalForm: "2026-07-16",
                        datatype: DatabaseXSDDatatype.date.typedLiteralDatatype
                    )
                ),
                graph: .iri("urn:calendar:active")
            )
        }
    }

    private let jobID = DatabaseUUID(
        high: 0x0011_2233_4455_6677,
        low: 0x8899_AABB_CCDD_EEFF
    )

    @Test("graph requests and responses round-trip by algorithm family")
    func graphFamilyRoundTrips() throws {
        let source = GraphAlgorithmOperation.Source(
            index: "eventGraph",
            partitions: [
                .init(number: 1, name: "runID", value: .string("run-1")),
            ],
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
                    graph: .named(.rdf(.blankNode("calendar-graph"))),
                    edgeLabel: .rdf(.iri("urn:calendar:related"))
                ),
                invocation: .shortestPath(
                    source: .rdf(.blankNode("event")),
                    target: .rdf(.iri("urn:event:target")),
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
                    cycles: [[
                        .identifier("a"),
                        .identifier("b"),
                        .identifier("a"),
                    ]],
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
                    components: [[.identifier("a"), .identifier("b")]],
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
        for response in responses { try expectRoundTrip(response) }
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

        try expectRoundTrip(
            OntologyExecuteOperation.Response.document(
                .init(
                    ontology: document.ontology,
                    revision: 5,
                    imports: document.imports,
                    axioms: document.axioms
                )
            )
        )
        try expectRoundTrip(
            OntologyExecuteOperation.Response.mutation(
                .init(commitVersion: 10, revision: 6)
            )
        )
        try expectRoundTrip(
            OntologyExecuteOperation.Response.inference(
                .init(inferredAxioms: [try quad], isComplete: true)
            )
        )
        try expectRoundTrip(
            OntologyExecuteOperation.Response.hierarchy(
                .init(entries: [.init(resource: "urn:Thing", depth: 1)])
            )
        )
        try expectRoundTrip(
            OntologyExecuteOperation.Response.validation(validationReport())
        )
    }

    @Test("SHACL requests and responses retain data and focus selections")
    func shaclFamilyRoundTrips() throws {
        let identity = PersistableIdentity(
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
                    partitions: [
                        .init(number: 1, name: "runID", value: .string("run-1")),
                    ],
                    graph: .named(.iri("urn:calendar:active"))
                ),
                focus: .nodes([.iri("urn:event:1")]),
                entailment: .rdfs
            ),
        ]
        for invocation in invocations {
            try expectRoundTrip(SHACLExecuteOperation.Request(invocation: invocation))
        }
        try expectRoundTrip(
            SHACLExecuteOperation.Response.shapes(
                .init(
                    graph: "urn:calendar:shapes",
                    revision: 3,
                    shapes: [try quad]
                )
            )
        )
        try expectRoundTrip(
            SHACLExecuteOperation.Response.validation(validationReport())
        )
    }

    @Test("command and maintenance payloads are statically shaped")
    func commandAndMaintenanceRoundTrip() throws {
        try expectRoundTrip(
            DatabaseCommandRequest(
                command: "calendar.activateImport",
                input: [0x72, 0x75, 0x6E, 0x2D, 0x31]
            )
        )
        try expectRoundTrip(
            CommandReadOperation.Response(
                output: [1],
                continuation: [2]
            )
        )
        try expectRoundTrip(
            CommandWriteOperation.Response(
                output: [1],
                commitVersion: 42
            )
        )

        let invocations: [MaintenanceExecuteOperation.Invocation] = [
            .migrationStatus,
            .runMigrations(targetVersion: .init(4, 0, 0)),
            .indexStatus(
                entity: "Event",
                index: nil,
                partitions: [
                    .init(number: 1, name: "runID", value: .string("run-1")),
                ]
            ),
            .rebuildIndex(
                entity: "Event",
                index: "startsAt",
                partitions: [
                    .init(number: 1, name: "runID", value: .string("run-1")),
                ],
                batchSize: 500
            ),
            .compact,
        ]
        for invocation in invocations {
            try expectRoundTrip(
                MaintenanceExecuteOperation.Request(invocation: invocation)
            )
        }
        try expectRoundTrip(
            MaintenanceExecuteOperation.Response.migrationStatus(
                .init(
                    currentVersion: .init(3, 0, 0),
                    targetVersion: .init(4, 0, 0),
                    pendingMigrationIdentifiers: ["calendar-v4"]
                )
            )
        )
        try expectRoundTrip(
            MaintenanceExecuteOperation.Response.migrationStatus(
                .init(
                    currentVersion: nil,
                    targetVersion: .init(1, 0, 0),
                    pendingMigrationIdentifiers: ["initial-schema"]
                )
            )
        )
        try expectRoundTrip(
            MaintenanceExecuteOperation.Response.indexStatus(
                .init(
                    indexes: [
                        .init(
                            entity: "Event",
                            index: "startsAt",
                            partitions: [
                                .init(
                                    number: 1,
                                    name: "runID",
                                    value: .string("run-1")
                                ),
                            ],
                            state: .ready,
                            indexedRecordCount: 10
                        ),
                    ]
                )
            )
        )
    }

    @Test("typed command frames are byte-identical to canonical raw command frames")
    func typedCommandFramesMatchCanonicalFrames() throws {
        let input = ActivateImportCommandInput(runID: "run-1", expectedRevision: 7)
        let output = ActivateImportCommandOutput(activated: true, importedCount: 128)
        let budget = DatabaseExecutionBudget(
            maximumRows: 512,
            maximumWorkUnits: 4_096,
            maximumIntermediateRows: 256,
            maximumIntermediateBytes: 1_048_576,
            timeoutMilliseconds: 2_000,
        )
        try expectRoundTrip(budget)
        let encodedInput = try DatabaseEnvelopeCodec.encode(input)
        let encodedOutput = try DatabaseEnvelopeCodec.encode(output)

        let rawRequest = try DatabaseEnvelopeCodec.encode(
            DatabaseCommandRequest(
                command: ActivateImportCommand.identifier,
                input: encodedInput,
                budget: budget
            )
        )
        let typedRequest = try DatabaseEnvelopeCodec.encode(
            DatabaseTypedCommandRequest<ActivateImportCommand>(
                input: input,
                budget: budget
            )
        )
        #expect(typedRequest == rawRequest)
        #expect(
            try DatabaseEnvelopeCodec.decode(
                DatabaseTypedCommandRequest<ActivateImportCommand>.self,
                from: rawRequest
            ).input == input
        )

        let rawResponse = try DatabaseEnvelopeCodec.encode(
            CommandWriteOperation.Response(
                output: encodedOutput,
                commitVersion: 42,
                continuation: [3, 2, 1]
            )
        )
        let typedResponse = try DatabaseEnvelopeCodec.encode(
            DatabaseTypedWriteCommandResponse(
                output: output,
                commitVersion: 42,
                continuation: [3, 2, 1]
            )
        )
        #expect(typedResponse == rawResponse)
        #expect(
            try DatabaseEnvelopeCodec.decode(
                DatabaseTypedWriteCommandResponse<ActivateImportCommandOutput>.self,
                from: rawResponse
            ).output == output
        )

        let rawReadResponse = try DatabaseEnvelopeCodec.encode(
            CommandReadOperation.Response(
                output: encodedOutput,
                continuation: [1, 2, 3]
            )
        )
        let typedReadResponse = try DatabaseEnvelopeCodec.encode(
            DatabaseTypedReadCommandResponse(
                output: output,
                continuation: [1, 2, 3]
            )
        )
        #expect(typedReadResponse == rawReadResponse)
    }

    @Test("durable job lifecycle uses canonical identifiers and outcomes")
    func jobFamilyRoundTrips() throws {
        let jobOperation = try DatabaseMaintenanceJobDescriptor
            .jobOperationIdentifier()
        let job = DatabaseJobIdentity(
            jobID: jobID,
            operation: jobOperation
        )
        let responseDigest = try DatabaseJobResultDigest(
            [UInt8](repeating: 0xaa, count: DatabaseJobResultDigest.byteCount)
        )
        let firstContinuation = try JobResultOperation.Continuation(
            job: job,
            responseDigest: responseDigest,
            nextChunkIndex: 1
        )
        try expectRoundTrip(
            JobStartOperation.Request(
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
            JobStartOperation.Response(jobID: jobID, operation: jobOperation)
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
                lastUnsuccessfulOutcomeCommitError: DatabaseRemoteError(
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
        let operation = try DatabaseJobOperationIdentifier(
            family: .maintenanceExecute,
            kind: "database.test.status"
        )
        let job = DatabaseJobIdentity(jobID: jobID, operation: operation)
        let now = DatabaseTimestamp(secondsSinceUnixEpoch: 1_784_131_200)
        let past = DatabaseTimestamp(secondsSinceUnixEpoch: 1_784_131_199)
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
            try DatabaseEnvelopeCodec.encode(pending)
        )
        invalidBytes[0] = JobStatusOperation.State.failed.rawValue
        #expect(throws: DatabaseWireError.invalidJobStatus) {
            try DatabaseEnvelopeCodec.decode(
                JobStatusOperation.Response.self,
                from: DatabaseBytes(invalidBytes)
            )
        }
    }

    @Test("job cancellation rejects impossible response combinations")
    func jobCancellationRejectsImpossibleCombinations() throws {
        let operation = try DatabaseJobOperationIdentifier(
            family: .maintenanceExecute,
            kind: "database.test.cancel"
        )
        let job = DatabaseJobIdentity(jobID: jobID, operation: operation)

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
            try DatabaseEnvelopeCodec.decode(
                JobCancelOperation.Response.self,
                from: invalidWire
            )
        }
    }

    @Test("capabilities advertise a canonical exact job operation set")
    func capabilitiesAdvertiseCanonicalJobOperations() throws {
        let command = try DatabaseJobOperationIdentifier(
            family: .commandWrite,
            kind: "calendar.import.validate"
        )
        let maintenance = try DatabaseMaintenanceJobDescriptor
            .jobOperationIdentifier()
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
            try DatabaseEnvelopeCodec.encode(reversed)
        }

        let duplicate = CapabilitiesDescribeOperation.Response(
            runtimeVersion: "1",
            features: [],
            jobOperations: [command, command]
        )
        #expect(throws: DatabaseWireError.nonCanonicalJobOperationSet) {
            try DatabaseEnvelopeCodec.encode(duplicate)
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
            try DatabaseEnvelopeCodec.decode(
                CapabilitiesDescribeOperation.Response.self,
                from: nonCanonicalWire
            )
        }
    }

    @Test("job result enforces digest, page, and continuation limits")
    func jobResultEnforcesFieldLimits() throws {
        let jobOperation = try DatabaseMaintenanceJobDescriptor
            .jobOperationIdentifier()
        let job = DatabaseJobIdentity(
            jobID: jobID,
            operation: jobOperation
        )
        #expect(
            throws: DatabaseWireError.invalidDigestLength(
                actual: DatabaseJobResultDigest.byteCount - 1,
                expected: DatabaseJobResultDigest.byteCount
            )
        ) {
            try DatabaseJobResultDigest(
                [UInt8](
                    repeating: 0,
                    count: DatabaseJobResultDigest.byteCount - 1
                )
            )
        }
        let digest = try DatabaseJobResultDigest(
            [UInt8](repeating: 0, count: DatabaseJobResultDigest.byteCount)
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
            responsePayloadPage: DatabaseBytes(
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
            try DatabaseEnvelopeCodec.encode(oversized)
        }
    }

    @Test("job result digest is canonical across page boundaries")
    func jobResultDigestIsCanonicalAcrossPageBoundaries() throws {
        var accumulator = DatabaseJobResultDigestAccumulator(
            operation: try DatabaseMaintenanceJobDescriptor
                .jobOperationIdentifier()
        )
        accumulator.update([0x01, 0x02])
        accumulator.update([0x03, 0x04, 0x05])

        #expect(
            accumulator.finalize().bytes.copyBytes() == [
                0xd7, 0x67, 0x5e, 0x66, 0x99, 0xfa, 0x0c, 0x28,
                0x69, 0x8a, 0x17, 0x04, 0x80, 0x12, 0x42, 0xbc,
                0x89, 0xe2, 0x54, 0xd5, 0xae, 0x45, 0xc6, 0x69,
                0x6d, 0xd0, 0xef, 0xd3, 0x55, 0x7a, 0x83, 0x34,
            ]
        )
    }

    @Test("job result digest matches a multi-block golden vector")
    func jobResultDigestMatchesMultiBlockGoldenVector() throws {
        let payload = DatabaseBytes(
            (0..<1_000).map { UInt8(truncatingIfNeeded: $0) }
        )
        var accumulator = DatabaseJobResultDigestAccumulator(
            operation: try DatabaseMaintenanceJobDescriptor
                .jobOperationIdentifier()
        )
        accumulator.update(payload.slice(0..<63))
        accumulator.update(payload.slice(63..<511))
        accumulator.update(payload.slice(511..<1_000))

        #expect(
            accumulator.finalize().bytes.copyBytes() == [
                0x53, 0x21, 0x1c, 0x8f, 0x6b, 0x47, 0x20, 0x81,
                0x9b, 0xd0, 0x0b, 0xb8, 0x82, 0x01, 0x4e, 0x0b,
                0xc2, 0xe1, 0x18, 0xb9, 0x51, 0xf7, 0x0a, 0xd6,
                0x26, 0x5c, 0x28, 0xe6, 0x09, 0x13, 0xf5, 0xc6,
            ]
        )
    }

    @Test("job operation identifiers enforce their canonical bounded grammar")
    func jobOperationIdentifierValidationIsStrict() throws {
        let valid = try DatabaseJobOperationIdentifier(
            family: .commandWrite,
            kind: "calendar.import.validate"
        )
        try expectRoundTrip(valid)

        #expect(throws: DatabaseWireError.invalidJobOperationKind) {
            try DatabaseJobOperationIdentifier(
                family: .commandWrite,
                kind: "Calendar.Import.Validate"
            )
        }
        #expect(throws: DatabaseWireError.invalidJobOperationKind) {
            try DatabaseJobOperationIdentifier(
                family: .commandWrite,
                kind: "calendar..validate"
            )
        }
        #expect(
            throws: DatabaseWireError.invalidJobOperationFamily(
                DatabaseOperationIdentifier.jobStart.rawValue
            )
        ) {
            try DatabaseJobOperationIdentifier(
                family: .jobStart,
                kind: "calendar.import.validate"
            )
        }

        let oversizedKind = String(
            repeating: "a",
            count: DatabaseJobOperationIdentifier.maximumKindUTF8Bytes + 1
        )
        let encoded = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter)
                throws(DatabaseWireError) in
            DatabaseOperationIdentifier.commandWrite.encode(into: &writer)
            try writer.writeString(oversizedKind)
        }
        #expect(
            throws: DatabaseWireError.stringTooLarge(
                actual: oversizedKind.utf8.count,
                maximum: DatabaseJobOperationIdentifier.maximumKindUTF8Bytes
            )
        ) {
            try DatabaseEnvelopeCodec.decode(
                DatabaseJobOperationIdentifier.self,
                from: encoded
            )
        }
    }

    @Test("job result binding includes job identity and operation kind")
    func jobResultBindingIsStrict() throws {
        let maintenance = try DatabaseMaintenanceJobDescriptor
            .jobOperationIdentifier()
        let calendar = try DatabaseJobOperationIdentifier(
            family: .maintenanceExecute,
            kind: "calendar.import.validate"
        )
        var maintenanceDigest = DatabaseJobResultDigestAccumulator(
            operation: maintenance
        )
        maintenanceDigest.update([1, 2, 3])
        var calendarDigest = DatabaseJobResultDigestAccumulator(
            operation: calendar
        )
        calendarDigest.update([1, 2, 3])
        #expect(maintenanceDigest.finalize() != calendarDigest.finalize())

        let digest = try DatabaseJobResultDigest(
            [UInt8](repeating: 0, count: DatabaseJobResultDigest.byteCount)
        )
        let expectedJob = DatabaseJobIdentity(
            jobID: jobID,
            operation: maintenance
        )
        let otherJob = DatabaseJobIdentity(
            jobID: DatabaseUUID(high: jobID.high ^ 1, low: jobID.low),
            operation: maintenance
        )
        let continuation = try JobResultOperation.Continuation(
            job: otherJob,
            responseDigest: digest,
            nextChunkIndex: 1
        )
        #expect(throws: DatabaseWireError.invalidResultPayload(2)) {
            try DatabaseEnvelopeCodec.encode(
                JobResultOperation.Request(
                    job: expectedJob,
                    continuation: continuation
                )
            )
        }
        #expect(throws: DatabaseWireError.invalidResultPayload(1)) {
            try DatabaseEnvelopeCodec.encode(
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

    @Test("typed job start is wire-identical without an inner payload buffer")
    func typedJobStartUsesTheCanonicalWireLayout() throws {
        let request = MaintenanceExecuteOperation.Request(invocation: .compact)
        let retryPolicy = JobStartOperation.RetryPolicy(
            maximumAttempts: 2,
            initialBackoffMilliseconds: 10,
            maximumBackoffMilliseconds: 20
        )
        let typedFrame = try DatabaseEnvelopeCodec.encodeRequest(
            DatabaseTypedJobStartOperation<
                DatabaseMaintenanceJobDescriptor
            >.self,
            requestID: 91,
            metadata: DatabaseRequestMetadata(traceID: "typed-job"),
            request: DatabaseTypedJobStartRequest(
                request: request,
                maximumSliceWorkUnits: 77,
                retryPolicy: retryPolicy
            )
        )

        let rawFrame = try DatabaseEnvelopeCodec.encodeRequest(
            JobStartOperation.self,
            requestID: 91,
            metadata: DatabaseRequestMetadata(traceID: "typed-job"),
            request: JobStartOperation.Request(
                operation: try DatabaseMaintenanceJobDescriptor
                    .jobOperationIdentifier(),
                requestPayload: try DatabaseEnvelopeCodec.encode(request),
                maximumSliceWorkUnits: 77,
                retryPolicy: retryPolicy
            )
        )

        #expect(typedFrame == rawFrame)
        let envelope = try DatabaseEnvelopeCodec.decodeRequest(typedFrame)
        let rawRequest = try DatabaseEnvelopeCodec.decode(
            JobStartOperation.Request.self,
            from: envelope.payload
        )
        #expect(
            try DatabaseEnvelopeCodec.decode(
                MaintenanceExecuteOperation.Request.self,
                from: rawRequest.requestPayload
            ) == request
        )
    }

    private func validationReport() -> DatabaseValidationReport {
        .init(
            conforms: false,
            issues: [
                .init(
                    severity: .violation,
                    code: "MIN_COUNT",
                    messages: ["Required value is missing"],
                    focusNode: .iri("urn:event:1"),
                    path: .sequence([
                        .predicate("urn:calendar:venue"),
                        .alternative([
                            .predicate("urn:calendar:name"),
                            .inverse(.predicate("urn:calendar:labelFor")),
                        ]),
                    ]),
                    value: .literal(
                        .init(
                            lexicalForm: "",
                            datatype: DatabaseXSDDatatype.string
                                .typedLiteralDatatype
                        )
                    ),
                    sourceConstraintComponent: "http://www.w3.org/ns/shacl#MinCountConstraintComponent",
                    sourceShape: .blankNode("event-shape")
                ),
            ]
        )
    }

    private func expectRoundTrip<Value>(
        _ value: Value
    ) throws where Value: DatabaseWireValue & Equatable {
        let encoded = try DatabaseEnvelopeCodec.encode(value)
        #expect(try DatabaseEnvelopeCodec.decode(Value.self, from: encoded) == value)
    }
}

private struct ActivateImportCommandInput: DatabaseWireValue, Equatable {
    let runID: String
    let expectedRevision: UInt64

    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeString(runID)
        writer.writeUInt64(expectedRevision)
    }

    init(runID: String, expectedRevision: UInt64) {
        self.runID = runID
        self.expectedRevision = expectedRevision
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            runID: try reader.readString(),
            expectedRevision: try reader.readUInt64()
        )
    }
}

private struct ActivateImportCommandOutput: DatabaseWireValue, Equatable {
    let activated: Bool
    let importedCount: UInt64

    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeBool(activated)
        writer.writeUInt64(importedCount)
    }

    init(activated: Bool, importedCount: UInt64) {
        self.activated = activated
        self.importedCount = importedCount
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            activated: try reader.readBool(),
            importedCount: try reader.readUInt64()
        )
    }
}

private enum ActivateImportCommand: DatabaseWriteCommandDescriptor {
    typealias Input = ActivateImportCommandInput
    typealias Output = ActivateImportCommandOutput

    static let identifier = "calendar.activateImport"
}
