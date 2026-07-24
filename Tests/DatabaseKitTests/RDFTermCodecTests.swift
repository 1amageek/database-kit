import DatabaseKit
import DatabaseTypes
import Synchronization
import Testing

@Suite("RDF term codec")
struct RDFTermCodecTests {
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

        let bytes = try RDFTermCodec.encode(term)

        #expect(try RDFTermCodec.decode(bytes) == term)
        #expect(bytes.count > 0)
    }

    @Test("the minimal zero-byte-free encoding is stable")
    func stableSpelling() throws {
        let bytes = try RDFTermCodec.encode(.iri(fixtureIRI("u:")))

        #expect(bytes == ByteString([2, 3, 0x75, 0x3A]))
        #expect(bytes.allSatisfy { $0 != 0 })
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
            let bytes = try RDFTermCodec.encode(term)
            #expect(bytes.allSatisfy { $0 != 0 })
            #expect(try RDFTermCodec.decode(bytes) == term)
        }
    }

    @Test("non-canonical varints and malformed values are rejected")
    func malformedValues() {
        #expect(
            throws: RDFTermCodecError.nonCanonicalVarint
        ) {
            _ = try RDFTermCodec.decode(
                ByteString([2, 0x83, 0x00, 0x75, 0x3A])
            )
        }
        #expect(
            throws: RDFTermCodecError.invalidIRI(.missingScheme)
        ) {
            _ = try RDFTermCodec.decode(
                ByteString([2, 4, 0x62, 0x61, 0x64])
            )
        }
        #expect(throws: RDFTermCodecError.invalidUTF8) {
            _ = try RDFTermCodec.decode(
                ByteString([2, 2, 0xFF])
            )
        }
        #expect(
            throws: RDFTermCodecError.nonCanonicalStringEncoding
        ) {
            _ = try RDFTermCodec.decode(
                ByteString([2, 2, 0])
            )
        }
    }

    @Test("encoding enforces all resource limits")
    func encodeValidation() throws {
        #expect(
            throws: RDFTermCodecError.maximumBytesExceeded(
                actual: 4,
                maximum: 3
            )
        ) {
            _ = try RDFTermCodec.encode(
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
            throws: RDFTermCodecError.maximumDepthExceeded(
                actual: 1,
                maximum: 0
            )
        ) {
            _ = try RDFTermCodec.encode(
                nested,
                limits: .init(maximumDepth: 0)
            )
        }
    }

    @Test("bytes-only validation enforces outer RDF roles")
    func bytesOnlyRoleValidation() throws {
        let iri = try RDFTermCodec.encode(
            .iri(fixtureIRI("urn:predicate"))
        )
        let literal = try RDFTermCodec.encode(
            .literal(RDFLiteral(
                lexicalForm: "value",
                datatype: .xsdString
            ))
        )

        try RDFTermCodec.validate(iri, role: .predicate)
        try RDFTermCodec.validate(literal, role: .object)
        #expect(
            throws: RDFTermCodecError.invalidRole(
                expected: .subject,
                actual: .literal
            )
        ) {
            try RDFTermCodec.validate(literal, role: .subject)
        }
        #expect(
            throws: RDFTermCodecError.invalidRole(
                expected: .predicate,
                actual: .blankNode
            )
        ) {
            try RDFTermCodec.validate(
                try RDFTermCodec.encode(
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
            throws: RDFTermCodecError.nonCanonicalLanguageTag
        ) {
            try RDFTermCodec.validate(uppercaseLanguageLiteral)
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
        let encoded = try RDFTermCodec.encode(term)
        let owner = BorrowCountingOwner(bytes: encoded.copyBytes())

        try RDFTermCodec.validate(
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
        let plan = try RDFTermCodec.encodingPlan(term)
        var sink = CollectingRDFEncodingSink()

        try RDFTermCodec.encode(plan, into: &sink)

        let owned = try RDFTermCodec.encode(term)
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
        let encoded = try RDFTermCodec.encode(nested)

        #expect(
            throws: RDFTermCodecError.maximumDepthExceeded(
                actual: 1,
                maximum: 0
            )
        ) {
            try RDFTermCodec.validate(
                encoded,
                limits: .init(maximumDepth: 0)
            )
        }
        #expect(
            throws: RDFTermCodecError.maximumObjectCountExceeded(
                actual: 4,
                maximum: 3
            )
        ) {
            try RDFTermCodec.validate(
                encoded,
                limits: .init(maximumObjectCount: 3)
            )
        }
        #expect(
            throws: RDFTermCodecError.maximumBytesExceeded(
                actual: encoded.count,
                maximum: encoded.count - 1
            )
        ) {
            try RDFTermCodec.validate(
                encoded,
                limits: .init(maximumBytes: encoded.count - 1)
            )
        }

        var trailing = encoded.copyBytes()
        trailing.append(1)
        #expect(throws: RDFTermCodecError.trailingBytes) {
            try RDFTermCodec.validate(ByteString(trailing))
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

        #expect(throws: RDFTermCodecError.invalidTripleSubject) {
            try RDFTermCodec.validate(invalidSubject)
        }
        #expect(throws: RDFTermCodecError.invalidTriplePredicate) {
            try RDFTermCodec.validate(invalidPredicate)
        }
    }

    private func validationError(
        for bytes: ByteString
    ) -> RDFTermCodecError? {
        do {
            try RDFTermCodec.validate(bytes)
            return nil
        } catch let error {
            return error
        }
    }

    private func decodingError(
        for bytes: ByteString
    ) -> RDFTermCodecError? {
        do {
            _ = try RDFTermCodec.decode(bytes)
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

private struct CollectingRDFEncodingSink: RDFTermEncodingSink {
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
