import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Synchronization
import Testing

@Suite("RDF term wire format")
struct RDFTermWireFormatTests {
    @Test("canonical terms round-trip from one owned payload")
    func roundTrip() throws {
        let term = RDFTerm.tripleTerm(
            subject: .blankNode(fixtureBlankNode("event")),
            predicate: fixturePredicate("urn:calendar:title"),
            object: .literal(RDFLiteral(
                lexicalForm: "東京",
                language: try RDFLanguageTag("JA")
            ))
        )

        let bytes = try RDFTermWireFormat.encode(term)

        #expect(try RDFTermWireFormat.decode(bytes) == term)
        #expect(bytes.count > 0)
    }

    @Test("the minimal zero-byte-free encoding is stable")
    func stableSpelling() throws {
        let bytes = try RDFTermWireFormat.encode(.iri(fixtureIRI("u:")))

        #expect(bytes == ByteString([2, 3, 0x75, 0x3A]))
        #expect(bytes.allSatisfy { $0 != 0 })
    }

    @Test("IRI bidirectional formatting characters preserve exact identity")
    func bidirectionalFormattingCharacters() throws {
        let term = RDFTerm.iri(
            fixtureIRI("urn:example:\u{202A}value\u{202C}")
        )
        let bytes = try RDFTermWireFormat.encode(term)

        #expect(try RDFTermWireFormat.decode(bytes) == term)
    }

    @Test("all term variants remain zero-byte-free and embedded NUL round-trips")
    func zeroByteFreeTerms() throws {
        let language = try RDFLanguageTag("en")
        let terms: [RDFTerm] = [
            .blankNode(fixtureBlankNode("node")),
            .iri(fixtureIRI("urn:example:value")),
            .literal(RDFLiteral(
                lexicalForm: "",
                datatype: XSDDatatype.string.typedLiteralDatatype
            )),
            .literal(RDFLiteral(
                lexicalForm: "before\0after",
                language: language
            )),
            .literal(RDFLiteral(
                lexicalForm: "directional",
                language: language,
                direction: .rightToLeft
            )),
            .tripleTerm(
                subject: .iri(fixtureIRI("urn:subject")),
                predicate: fixturePredicate("urn:predicate"),
                object: .blankNode(fixtureBlankNode("object"))
            ),
        ]

        for term in terms {
            let bytes = try RDFTermWireFormat.encode(term)
            #expect(bytes.allSatisfy { $0 != 0 })
            #expect(try RDFTermWireFormat.decode(bytes) == term)
        }
    }

    @Test("non-canonical varints and malformed values are rejected")
    func malformedValues() {
        #expect(
            throws: RDFTermWireError.nonCanonicalVarint
        ) {
            _ = try RDFTermWireFormat.decode(
                ByteString([2, 0x83, 0x00, 0x75, 0x3A])
            )
        }
        #expect(
            throws: RDFTermWireError.invalidIRI(.missingScheme)
        ) {
            _ = try RDFTermWireFormat.decode(
                ByteString([2, 4, 0x62, 0x61, 0x64])
            )
        }
        #expect(throws: RDFTermWireError.invalidUTF8) {
            _ = try RDFTermWireFormat.decode(
                ByteString([2, 2, 0xFF])
            )
        }
        #expect(
            throws: RDFTermWireError.nonCanonicalStringEncoding
        ) {
            _ = try RDFTermWireFormat.decode(
                ByteString([2, 2, 0])
            )
        }
    }

    @Test("encoding enforces all resource limits")
    func encodeValidation() throws {
        #expect(
            throws: RDFTermWireError.maximumBytesExceeded(
                actual: 4,
                maximum: 3
            )
        ) {
            _ = try RDFTermWireFormat.encode(
                .iri(fixtureIRI("u:")),
                limits: .init(maximumBytes: 3)
            )
        }

        let nested = RDFTerm.tripleTerm(
            subject: .iri(fixtureIRI("urn:subject")),
            predicate: fixturePredicate("urn:predicate"),
            object: .iri(fixtureIRI("urn:object"))
        )
        #expect(
            throws: RDFTermWireError.maximumDepthExceeded(
                actual: 1,
                maximum: 0
            )
        ) {
            _ = try RDFTermWireFormat.encode(
                nested,
                limits: .init(maximumDepth: 0)
            )
        }
    }

    @Test("bytes-only validation enforces outer RDF roles")
    func bytesOnlyRoleValidation() throws {
        let iri = try RDFTermWireFormat.encode(
            .iri(fixtureIRI("urn:predicate"))
        )
        let literal = try RDFTermWireFormat.encode(
            .literal(RDFLiteral(
                lexicalForm: "value",
                datatype: .xsdString
            ))
        )

        try RDFTermWireFormat.validate(iri, role: .predicate)
        try RDFTermWireFormat.validate(literal, role: .object)
        #expect(
            throws: RDFTermWireError.invalidRole(
                expected: .subject,
                actual: .literal
            )
        ) {
            try RDFTermWireFormat.validate(literal, role: .subject)
        }
        #expect(
            throws: RDFTermWireError.invalidRole(
                expected: .predicate,
                actual: .blankNode
            )
        ) {
            try RDFTermWireFormat.validate(
                try RDFTermWireFormat.encode(
                    .blankNode(fixtureBlankNode("node"))
                ),
                role: .predicate
            )
        }
    }

    @Test("bytes-only validation rejects non-canonical language tags")
    func bytesOnlyLanguageValidation() {
        let uppercaseLanguageLiteral = ByteString([
            3,
            1,
            2,
            3, 0x45, 0x4E,
        ])

        #expect(
            throws: RDFTermWireError.nonCanonicalLanguageTag
        ) {
            try RDFTermWireFormat.validate(uppercaseLanguageLiteral)
        }
    }

    @Test("bytes-only validation uses one scoped owner borrow")
    func bytesOnlyValidationUsesOneBorrow() throws {
        let term = RDFTerm.tripleTerm(
            subject: .iri(fixtureIRI("urn:subject")),
            predicate: fixturePredicate("urn:predicate"),
            object: .literal(RDFLiteral(
                lexicalForm: "東京\0event",
                language: try RDFLanguageTag("ja")
            ))
        )
        let encoded = try RDFTermWireFormat.encode(term)
        let owner = BorrowCountingOwner(bytes: encoded.copyBytes())

        try RDFTermWireFormat.validate(
            ByteString(retaining: owner),
            role: .object
        )

        #expect(owner.borrowCount == 1)
    }

    @Test("streaming output is byte-identical to owned canonical output")
    func streamingOutputMatchesOwnedOutput() throws {
        let term = RDFTerm.tripleTerm(
            subject: .blankNode(fixtureBlankNode("event")),
            predicate: fixturePredicate("urn:calendar:title"),
            object: .literal(RDFLiteral(
                lexicalForm: "before\0東京after",
                language: try RDFLanguageTag("ja")
            ))
        )
        let plan = try RDFTermWireFormat.encodingPlan(term)
        var sink = CollectingRDFEncodingSink()

        try RDFTermWireFormat.encode(plan, into: &sink)

        let owned = try RDFTermWireFormat.encode(term)
        #expect(plan.byteCount == owned.count)
        #expect(ByteString(sink.bytes) == owned)
    }

    @Test("validation and semantic decoding reject the same malformed corpus")
    func validationAndDecodingParity() {
        let malformed: [ByteString] = [
            [],
            [0xFF],
            [2],
            [2, 4, 0x62, 0x61],
            [2, 4, 0x62, 0x61, 0x64],
            [3, 2, 0x78, 1],
            [3, 1, 2, 3, 0x45, 0x4E],
            [4, 3, 2, 0x78, 1, 4, 0x75, 0x3A, 0x70, 2, 4, 0x75, 0x3A, 0x6F],
            [4, 2, 4, 0x75, 0x3A, 0x73, 1, 2, 0x70, 2, 4, 0x75, 0x3A, 0x6F],
        ]

        for bytes in malformed {
            #expect(validationError(for: bytes) == decodingError(for: bytes))
        }
    }

    @Test("byte validation enforces depth object byte and trailing limits")
    func byteValidationLimits() throws {
        let nested = RDFTerm.tripleTerm(
            subject: .iri(fixtureIRI("urn:subject")),
            predicate: fixturePredicate("urn:predicate"),
            object: .iri(fixtureIRI("urn:object"))
        )
        let encoded = try RDFTermWireFormat.encode(nested)

        #expect(
            throws: RDFTermWireError.maximumDepthExceeded(
                actual: 1,
                maximum: 0
            )
        ) {
            try RDFTermWireFormat.validate(
                encoded,
                limits: .init(maximumDepth: 0)
            )
        }
        #expect(
            throws: RDFTermWireError.maximumObjectCountExceeded(
                actual: 4,
                maximum: 3
            )
        ) {
            try RDFTermWireFormat.validate(
                encoded,
                limits: .init(maximumObjectCount: 3)
            )
        }
        #expect(
            throws: RDFTermWireError.maximumBytesExceeded(
                actual: encoded.count,
                maximum: encoded.count - 1
            )
        ) {
            try RDFTermWireFormat.validate(
                encoded,
                limits: .init(maximumBytes: encoded.count - 1)
            )
        }

        var trailing = encoded.copyBytes()
        trailing.append(1)
        #expect(throws: RDFTermWireError.trailingBytes) {
            try RDFTermWireFormat.validate(ByteString(trailing))
        }
    }

    @Test("nested triple role errors remain exact")
    func nestedTripleRoleErrors() {
        let invalidSubject = ByteString([
            4,
            3, 2, 0x78, 1, 4, 0x75, 0x3A, 0x74,
            2, 4, 0x75, 0x3A, 0x70,
            2, 4, 0x75, 0x3A, 0x6F,
        ])
        let invalidPredicate = ByteString([
            4,
            2, 4, 0x75, 0x3A, 0x73,
            1, 2, 0x70,
            2, 4, 0x75, 0x3A, 0x6F,
        ])

        #expect(throws: RDFTermWireError.invalidTripleSubject) {
            try RDFTermWireFormat.validate(invalidSubject)
        }
        #expect(throws: RDFTermWireError.invalidTriplePredicate) {
            try RDFTermWireFormat.validate(invalidPredicate)
        }
    }

    private func validationError(
        for bytes: ByteString
    ) -> RDFTermWireError? {
        do {
            try RDFTermWireFormat.validate(bytes)
            return nil
        } catch let error {
            return error
        }
    }

    private func decodingError(
        for bytes: ByteString
    ) -> RDFTermWireError? {
        do {
            _ = try RDFTermWireFormat.decode(bytes)
            return nil
        } catch let error {
            return error
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

    private func fixturePredicate(_ rawValue: String) -> RDFPredicateIRI {
        RDFPredicateIRI(fixtureIRI(rawValue))
    }
}

private struct CollectingRDFEncodingSink: RDFTermWireSink {
    var bytes: [UInt8] = []

    mutating func write(_ byte: UInt8) {
        bytes.append(byte)
    }

    mutating func write(_ bytes: UnsafeRawBufferPointer) {
        self.bytes.append(contentsOf: bytes)
    }
}

private final class BorrowCountingOwner: ByteStringOwner {
    let bytes: [UInt8]
    private let state = Mutex(0)

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var count: Int { bytes.count }

    var borrowCount: Int {
        state.withLock { $0 }
    }

    func borrowBytes(
        _ body: (UnsafeRawBufferPointer) throws -> Void
    ) rethrows {
        state.withLock { $0 += 1 }
        try bytes.withUnsafeBytes(body)
    }
}
