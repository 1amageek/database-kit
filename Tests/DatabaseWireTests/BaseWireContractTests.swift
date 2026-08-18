#if DATABASE_KIT_MULTIPLE_BASES
import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("Base, Composition, and Security wire contracts")
struct BaseWireContractTests {
    private let query = QueryExecuteOperation.Request(
        input: .text(language: .sql, statement: "SELECT 1")
    )

    @Test("Every request carries one explicit operation target")
    func requestTargetsRoundTrip() throws {
        let baseID = try Base.ID("company-a")
        let compositionID = try Base.Composition.ID("shared")
        let targets: [DatabaseOperationTarget] = [
            .database,
            .base(baseID),
            .composition(.named(compositionID)),
            .composition(try .derived([baseID])),
        ]

        for (index, target) in targets.enumerated() {
            let frame = try DatabaseWireEncoder().encodeRequest(
                DatabaseOperationCatalog.queryExecute,
                requestID: UInt64(index + 1),
                target: target,
                request: query
            )
            let decoded = try DatabaseWireDecoder().decodeRequest(
                DatabaseOperationCatalog.queryExecute,
                from: frame
            )
            #expect(decoded.target == target)
            #expect(decoded.request == query)
        }
    }

    @Test("Composition targets have fixed v4 selection encodings")
    func compositionTargetGoldenVectors() throws {
        let baseA = try Base.ID("company-a")
        let baseB = try Base.ID("company-b")
        let compositionID = try Base.Composition.ID("shared")

        #expect(
            try EnvelopeWireFormat.encode(
                DatabaseOperationTarget.composition(.named(compositionID))
            ) == [
                0x02,
                0x00,
                0x06, 0x00, 0x00, 0x00,
                0x73, 0x68, 0x61, 0x72, 0x65, 0x64,
            ]
        )
        #expect(
            try EnvelopeWireFormat.encode(
                DatabaseOperationTarget.composition(
                    try .derived([baseB, baseA])
                )
            ) == [
                0x02,
                0x01,
                0x02, 0x00, 0x00, 0x00,
                0x09, 0x00, 0x00, 0x00,
                0x63, 0x6f, 0x6d, 0x70, 0x61, 0x6e, 0x79, 0x2d, 0x61,
                0x09, 0x00, 0x00, 0x00,
                0x63, 0x6f, 0x6d, 0x70, 0x61, 0x6e, 0x79, 0x2d, 0x62,
            ]
        )
    }

    @Test("Composition provenance has fixed v4 resolution encodings")
    func compositionResolutionGoldenVectors() throws {
        let baseA = try Base.ID("company-a")
        let baseB = try Base.ID("company-b")
        let compositionID = try Base.Composition.ID("shared")

        #expect(
            try EnvelopeWireFormat.encode(
                CompositionResolution.named(
                    id: compositionID,
                    generation: 12,
                    bases: [baseA, baseB]
                )
            ) == [
                0x00,
                0x06, 0x00, 0x00, 0x00,
                0x73, 0x68, 0x61, 0x72, 0x65, 0x64,
                0x0c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x02, 0x00, 0x00, 0x00,
                0x09, 0x00, 0x00, 0x00,
                0x63, 0x6f, 0x6d, 0x70, 0x61, 0x6e, 0x79, 0x2d, 0x61,
                0x09, 0x00, 0x00, 0x00,
                0x63, 0x6f, 0x6d, 0x70, 0x61, 0x6e, 0x79, 0x2d, 0x62,
            ]
        )
        #expect(
            try EnvelopeWireFormat.encode(
                CompositionResolution.derived([baseA, baseB])
            ) == [
                0x01,
                0x02, 0x00, 0x00, 0x00,
                0x09, 0x00, 0x00, 0x00,
                0x63, 0x6f, 0x6d, 0x70, 0x61, 0x6e, 0x79, 0x2d, 0x61,
                0x09, 0x00, 0x00, 0x00,
                0x63, 0x6f, 0x6d, 0x70, 0x61, 0x6e, 0x79, 0x2d, 0x62,
            ]
        )
    }

    @Test("A legacy Base-less request frame is rejected")
    func baseLessRequestIsRejected() {
        let oldCapabilitiesFrame: ByteString = [
            0x44, 0x42, 0x57, 0x52,
            0x01, 0x00,
            0x01,
            0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x01, 0x01,
            0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00,
        ]

        #expect(throws: DatabaseWireError.self) {
            try DatabaseWireDecoder().decodeRequest(
                DatabaseOperationCatalog.capabilitiesDescribe,
                from: oldCapabilitiesFrame
            )
        }
    }

    @Test("Security wire rejects empty and unknown access bits")
    func accessBitsAreClosed() throws {
        #expect(throws: DatabaseWireError.invalidSecurityAccess(0)) {
            try EnvelopeWireFormat.decode(Security.Access.self, from: [0])
        }
        #expect(throws: DatabaseWireError.invalidSecurityAccess(0x80)) {
            try EnvelopeWireFormat.decode(Security.Access.self, from: [0x80])
        }

        let access: Security.Access = [.read, .administer]
        #expect(
            try EnvelopeWireFormat.decode(
                Security.Access.self,
                from: EnvelopeWireFormat.encode(access)
            ) == access
        )
    }

    @Test("Base create requires a canonical administering initial Grant")
    func initialBaseGrantContract() throws {
        let baseID = try Base.ID("company-a")
        let placementID = try Base.Placement.ID("primary")
        let subject = Security.Subject.principal("alice")
        let readOnly = Security.Grant(
            subject: subject,
            resource: .base(baseID),
            access: .read
        )
        let administering = Security.Grant(
            subject: subject,
            resource: .base(baseID),
            access: .administer
        )

        #expect(throws: DatabaseWireError.invalidInitialBaseGrants) {
            try DatabaseOperationCatalog.baseExecute.encodeRequestPayload(
                .init(
                    invocation: .create(
                        baseID: baseID,
                        placementID: placementID,
                        initialGrants: [readOnly],
                        expectedRevision: 0,
                        idempotencyKey: "create-company-a"
                    )
                )
            )
        }

        let request = BaseExecuteOperation.Request(
            invocation: .create(
                baseID: baseID,
                placementID: placementID,
                initialGrants: [readOnly, administering],
                expectedRevision: 0,
                idempotencyKey: "create-company-a"
            )
        )
        try expectRoundTrip(request)
    }

    @Test("The three administrative operation families round-trip")
    func administrativeFamiliesRoundTrip() throws {
        let baseA = try Base.ID("company-a")
        let baseB = try Base.ID("company-b")
        let composition = try Base.Composition(
            id: Base.Composition.ID("shared"),
            bases: [baseA, baseB]
        )
        let grant = Security.Grant(
            subject: .principalRole("analyst"),
            resource: .base(baseA),
            access: .read
        )

        try expectRoundTrip(
            CompositionExecuteOperation.Request(
                invocation: .create(
                    composition: composition,
                    expectedRevision: 0,
                    idempotencyKey: "create-shared"
                )
            )
        )
        try expectRoundTrip(
            GrantExecuteOperation.Request(
                invocation: .grant(
                    grant,
                    expectedRevision: 7,
                    idempotencyKey: "grant-analyst"
                )
            )
        )
        try expectRoundTrip(
            GrantExecuteOperation.Request(invocation: .effective)
        )
        try expectRoundTrip(
            GrantExecuteOperation.Response.effective(
                .init(access: .read, contributors: [grant])
            )
        )
    }

    @Test("Empty administrative result sets round-trip without trapping")
    func emptyAdministrativeResultSetsRoundTrip() throws {
        try expectRoundTrip(BaseExecuteOperation.Response.placements([]))
        try expectRoundTrip(BaseExecuteOperation.Response.bases([]))
        try expectRoundTrip(
            CompositionExecuteOperation.Response.compositions([])
        )
        try expectRoundTrip(
            GrantExecuteOperation.Response.direct(
                .init(revision: 0, grants: [])
            )
        )
    }

    @Test("Federated read points require canonical unique domain order")
    func federatedReadPointOrder() throws {
        let primary = try DomainReadPoint(
            domainID: "primary",
            position: .version(10)
        )
        let secondary = try DomainReadPoint(
            domainID: "secondary",
            position: .opaque([0x01])
        )
        let canonical = DatabaseReadConsistency.federated([
            primary,
            secondary,
        ])

        try expectRoundTrip(canonical)
        #expect(throws: DatabaseWireError.invalidFederatedReadPoints) {
            try EnvelopeWireFormat.encode(
                DatabaseReadConsistency.federated([secondary, primary])
            )
        }
        #expect(throws: DatabaseWireError.invalidFederatedReadPoints) {
            try EnvelopeWireFormat.encode(
                DatabaseReadConsistency.federated([primary, primary])
            )
        }
    }

    @Test("Composition provenance uses one Base table and row ordinals")
    func compositionProvenanceRoundTrip() throws {
        let baseA = try Base.ID("company-a")
        let baseB = try Base.ID("company-b")
        let compositionID = try Base.Composition.ID("shared")
        let provenance = try CompositionPageProvenance(
            composition: try .named(
                id: compositionID,
                generation: 12,
                bases: [baseA, baseB]
            ),
            origins: [
                .source(baseA),
                .derived(contributors: [baseA, baseB]),
            ]
        )
        var materializedOrigins = provenance.makeOriginIterator()
        #expect(try materializedOrigins.next() == .source(baseA))
        #expect(
            try materializedOrigins.next()
                == .derived(contributors: [baseA, baseB])
        )
        #expect(try materializedOrigins.next() == nil)

        let page = try QueryRowPage(
            columns: [.init(number: 1, name: "value")],
            rows: [
                QueryRow(values: [.string("a")], version: [0x01]),
                QueryRow(values: [.string("shared")], version: [0x02]),
            ],
            continuation: [0x03],
            provenance: provenance,
            consistency: .federated([
                try DomainReadPoint(domainID: "primary", position: .version(4)),
                try DomainReadPoint(domainID: "secondary", position: .version(8)),
            ])
        )

        let encoded = try EnvelopeWireFormat.encode(
            QueryExecuteOperation.Response.rows(page)
        )
        let response = try EnvelopeWireFormat.decode(
            QueryExecuteOperation.Response.self,
            from: encoded
        )
        guard case .rows(let decoded) = response else {
            Issue.record("Expected a row result")
            return
        }
        #expect(decoded.provenance?.baseIDs == [baseA, baseB])
        #expect(decoded.provenance?.composition.namedID == compositionID)
        #expect(decoded.provenance?.composition.generation == 12)

        var origins = try #require(decoded.provenance).makeOriginIterator()
        #expect(try origins.next() == .source(baseA))
        #expect(
            try origins.next() == .derived(contributors: [baseA, baseB])
        )
        #expect(try origins.next() == nil)
    }

    @Test("Job digests are separated by target")
    func jobDigestIncludesTarget() throws {
        let operation = JobOperations.maintenance.identifier
        let baseID = try Base.ID("company-a")
        var database = JobResultDigestAccumulator(
            operation: operation,
            target: .database
        )
        var base = JobResultDigestAccumulator(
            operation: operation,
            target: .base(baseID)
        )
        let secondBaseID = try Base.ID("company-b")
        var oneMember = JobResultDigestAccumulator(
            operation: operation,
            target: .composition(try .derived([baseID]))
        )
        var twoMembers = JobResultDigestAccumulator(
            operation: operation,
            target: .composition(try .derived([baseID, secondBaseID]))
        )
        database.update([1, 2, 3])
        base.update([1, 2, 3])
        oneMember.update([1, 2, 3])
        twoMembers.update([1, 2, 3])

        #expect(database.finalize() != base.finalize())
        #expect(oneMember.finalize() != twoMembers.finalize())
    }

    private func expectRoundTrip<Value: WireValue & Equatable>(
        _ value: Value
    ) throws {
        let bytes = try EnvelopeWireFormat.encode(value)
        #expect(try EnvelopeWireFormat.decode(Value.self, from: bytes) == value)
    }
}
#endif
