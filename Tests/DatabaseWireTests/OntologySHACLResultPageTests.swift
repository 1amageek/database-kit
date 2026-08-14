import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("Owner-retaining ontology and SHACL results")
struct OntologySHACLResultPageTests {
    @Test("ontology document page retains axioms in the response frame")
    func ontologyDocumentPageRetainsAxioms() throws {
        let expectedQuad = try quad()
        let response = OntologyExecuteOperation.Response.document(
            .init(
                ontology: "urn:ontology",
                revision: 2,
                imports: ["urn:import"],
                axioms: [expectedQuad]
            )
        )
        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperationCatalog.ontologyExecute,
            requestID: 121,
            response: response
        )
        let decoded = try DatabaseWireDecoder().decodeResponse(
            DatabaseOperationCatalog.ontologyExecute,
            from: frame,
            matching: 121
        )
        guard case .success(.document(let page)) = decoded else {
            Issue.record("Expected an ontology document page")
            return
        }
        try expectSharedBacking(
            child: #require(page.retainedEncodedAxioms),
            owner: frame
        )

        #expect(page.axiomCount == 1)
        var axioms = page.makeAxiomIterator()
        #expect(try axioms.next() == expectedQuad)
        #expect(try axioms.next() == nil)
    }

    @Test("SHACL shapes page retains quads in the response frame")
    func shapesPageRetainsQuads() throws {
        let expectedQuad = try quad()
        let response = SHACLExecuteOperation.Response.shapes(
            .init(
                graph: "urn:shapes",
                revision: 3,
                shapes: [expectedQuad]
            )
        )
        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperationCatalog.shaclExecute,
            requestID: 122,
            response: response
        )
        let decoded = try DatabaseWireDecoder().decodeResponse(
            DatabaseOperationCatalog.shaclExecute,
            from: frame,
            matching: 122
        )
        guard case .success(.shapes(let page)) = decoded else {
            Issue.record("Expected a SHACL shapes page")
            return
        }
        try expectSharedBacking(
            child: #require(page.retainedEncodedShapes),
            owner: frame
        )

        #expect(page.shapeCount == 1)
        var shapes = page.makeShapeIterator()
        #expect(try shapes.next() == expectedQuad)
        #expect(try shapes.next() == nil)
    }

    @Test("validation report retains issues and validates nested paths")
    func validationReportRetainsIssues() throws {
        let issue = ValidationReport.Issue(
            severity: .violation,
            code: "PATH",
            messages: ["Invalid path"],
            path: .sequence(
                try SHACLPathList([
                    .predicate(try RDFPredicateIRI("urn:first")),
                    .inverse(
                        .predicate(try RDFPredicateIRI("urn:second"))
                    ),
                ])
            )
        )
        let response = SHACLExecuteOperation.Response.validation(
            ValidationReport(conforms: false, issues: [issue])
        )
        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperationCatalog.shaclExecute,
            requestID: 123,
            response: response
        )
        let decoded = try DatabaseWireDecoder().decodeResponse(
            DatabaseOperationCatalog.shaclExecute,
            from: frame,
            matching: 123
        )
        guard case .success(.validation(let report)) = decoded else {
            Issue.record("Expected a validation report")
            return
        }
        try expectSharedBacking(
            child: #require(report.retainedEncodedIssues),
            owner: frame
        )

        #expect(report.issueCount == 1)
        var issues = report.makeIssueIterator()
        #expect(try issues.next() == issue)
        #expect(try issues.next() == nil)
    }

    @Test("invalid nested SHACL paths are rejected before issue iteration")
    func invalidNestedPathIsRejectedDuringAcceptance() throws {
        let issue = ValidationReport.Issue(
            severity: .violation,
            code: "PATH",
            path: .inverse(
                .predicate(try RDFPredicateIRI("urn:unique-path"))
            )
        )
        let response = SHACLExecuteOperation.Response.validation(
            ValidationReport(conforms: false, issues: [issue])
        )
        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperationCatalog.shaclExecute,
            requestID: 124,
            response: response
        )
        var corrupted = Array(frame)
        let marker = Array("urn:unique-path".utf8)
        let markerIndex = try #require(firstIndex(of: marker, in: corrupted))
        #expect(corrupted[markerIndex - 5] == 1)
        corrupted[markerIndex - 5] = 0xFF

        #expect(throws: DatabaseWireError.invalidValueTag(0xFF)) {
            _ = try DatabaseWireDecoder().decodeResponse(
                DatabaseOperationCatalog.shaclExecute,
                from: ByteString(corrupted),
                matching: 124
            )
        }
    }

    private func quad() throws -> RDFQuad {
        RDFQuad(
            subject: .iri(try RDFIRI("urn:subject")),
            predicate: RDFPredicateIRI(try RDFIRI("urn:predicate")),
            object: .literal(
                RDFLiteral(
                    lexicalForm: "value",
                    annotation: .typed(
                        XSDDatatype.string.typedLiteralDatatype
                    )
                )
            )
        )
    }

    private func expectSharedBacking(
        child: ByteString,
        owner: ByteString
    ) throws {
        let ownerRange = try #require(
            owner.withUnsafeBytes { bytes -> Range<UInt>? in
                guard let baseAddress = bytes.baseAddress else {
                    return nil
                }
                let start = UInt(bitPattern: baseAddress)
                return start..<(start + UInt(bytes.count))
            }
        )
        let childAddress = try #require(
            child.withUnsafeBytes { bytes in
                bytes.baseAddress.map { UInt(bitPattern: $0) }
            }
        )
        #expect(ownerRange.contains(childAddress))
    }

    private func firstIndex(
        of pattern: [UInt8],
        in bytes: [UInt8]
    ) -> Int? {
        guard pattern.count <= bytes.count else {
            return nil
        }
        for index in 0...(bytes.count - pattern.count) {
            if bytes[index..<(index + pattern.count)]
                .elementsEqual(pattern) {
                return index
            }
        }
        return nil
    }
}
