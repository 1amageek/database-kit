import DatabaseValue
import Synchronization
import Testing

@Suite("Database RDF term codec")
struct DatabaseRDFTermCodecTests {
    @Test("canonical terms round-trip from one owned payload")
    func roundTrip() throws {
        let term = DatabaseRDFTerm.tripleTerm(
            subject: .blankNode("event"),
            predicate: .iri("urn:calendar:title"),
            object: .literal(DatabaseRDFLiteral(
                lexicalForm: "東京",
                language: try DatabaseRDFLanguageTag("JA")
            ))
        )

        let bytes = try DatabaseRDFTermCodec.encode(term)

        #expect(try DatabaseRDFTermCodec.decode(bytes) == term)
        if case .array(_, let range) = bytes.sharedStorage {
            #expect(range.count == bytes.count)
        } else {
            Issue.record("Expected the codec to own one exact array payload")
        }
    }

    @Test("the minimal zero-byte-free encoding is stable")
    func stableSpelling() throws {
        let bytes = try DatabaseRDFTermCodec.encode(.iri("u:"))

        #expect(bytes == DatabaseBytes([2, 3, 0x75, 0x3A]))
        #expect(bytes.allSatisfy { $0 != 0 })
    }

    @Test("all term variants remain zero-byte-free and embedded NUL round-trips")
    func zeroByteFreeTerms() throws {
        let language = try DatabaseRDFLanguageTag("en")
        let terms: [DatabaseRDFTerm] = [
            .blankNode("node"),
            .iri("urn:example:value"),
            .literal(DatabaseRDFLiteral(
                lexicalForm: "",
                datatype: DatabaseXSDDatatype.string.typedLiteralDatatype
            )),
            .literal(DatabaseRDFLiteral(
                lexicalForm: "before\0after",
                language: language
            )),
            .literal(DatabaseRDFLiteral(
                lexicalForm: "directional",
                language: language,
                direction: .rightToLeft
            )),
            .tripleTerm(
                subject: .iri("urn:subject"),
                predicate: .iri("urn:predicate"),
                object: .blankNode("object")
            ),
        ]

        for term in terms {
            let bytes = try DatabaseRDFTermCodec.encode(term)
            #expect(bytes.allSatisfy { $0 != 0 })
            #expect(try DatabaseRDFTermCodec.decode(bytes) == term)
        }
    }

    @Test("non-canonical varints and malformed values are rejected")
    func malformedValues() {
        #expect(
            throws: DatabaseRDFTermCodecError.nonCanonicalVarint
        ) {
            _ = try DatabaseRDFTermCodec.decode(
                DatabaseBytes([2, 0x83, 0x00, 0x75, 0x3A])
            )
        }
        #expect(
            throws: DatabaseRDFTermCodecError.invalidIRI(.missingScheme)
        ) {
            _ = try DatabaseRDFTermCodec.decode(
                DatabaseBytes([2, 4, 0x62, 0x61, 0x64])
            )
        }
        #expect(throws: DatabaseRDFTermCodecError.invalidUTF8) {
            _ = try DatabaseRDFTermCodec.decode(
                DatabaseBytes([2, 2, 0xFF])
            )
        }
        #expect(
            throws: DatabaseRDFTermCodecError.nonCanonicalStringEncoding
        ) {
            _ = try DatabaseRDFTermCodec.decode(
                DatabaseBytes([2, 2, 0])
            )
        }
    }

    @Test("encoding validates RDF roles and all resource limits")
    func encodeValidation() throws {
        let invalidPredicate = DatabaseRDFTerm.tripleTerm(
            subject: .iri("urn:subject"),
            predicate: .blankNode("predicate"),
            object: .iri("urn:object")
        )
        #expect(
            throws: DatabaseRDFTermCodecError.invalidTriplePredicate
        ) {
            _ = try DatabaseRDFTermCodec.encode(invalidPredicate)
        }
        #expect(
            throws: DatabaseRDFTermCodecError.maximumBytesExceeded(
                actual: 4,
                maximum: 3
            )
        ) {
            _ = try DatabaseRDFTermCodec.encode(
                .iri("u:"),
                limits: .init(maximumBytes: 3)
            )
        }

        let nested = DatabaseRDFTerm.tripleTerm(
            subject: .iri("urn:subject"),
            predicate: .iri("urn:predicate"),
            object: .iri("urn:object")
        )
        #expect(
            throws: DatabaseRDFTermCodecError.maximumDepthExceeded(
                actual: 1,
                maximum: 0
            )
        ) {
            _ = try DatabaseRDFTermCodec.encode(
                nested,
                limits: .init(maximumDepth: 0)
            )
        }
    }

    @Test("bytes-only validation enforces outer RDF roles")
    func bytesOnlyRoleValidation() throws {
        let iri = try DatabaseRDFTermCodec.encode(.iri("urn:predicate"))
        let literal = try DatabaseRDFTermCodec.encode(
            .literal(DatabaseRDFLiteral(
                lexicalForm: "value",
                datatype: .xsdString
            ))
        )

        try DatabaseRDFTermCodec.validate(iri, role: .predicate)
        try DatabaseRDFTermCodec.validate(literal, role: .object)
        #expect(
            throws: DatabaseRDFTermCodecError.invalidRole(
                expected: .subject,
                actual: .literal
            )
        ) {
            try DatabaseRDFTermCodec.validate(literal, role: .subject)
        }
        #expect(
            throws: DatabaseRDFTermCodecError.invalidRole(
                expected: .predicate,
                actual: .blankNode
            )
        ) {
            try DatabaseRDFTermCodec.validate(
                try DatabaseRDFTermCodec.encode(.blankNode("node")),
                role: .predicate
            )
        }
    }

    @Test("bytes-only validation rejects non-canonical language tags")
    func bytesOnlyLanguageValidation() {
        let uppercaseLanguageLiteral = DatabaseBytes([
            3,
            1,
            2,
            3, 0x45, 0x4E,
        ])

        #expect(
            throws: DatabaseRDFTermCodecError.nonCanonicalLanguageTag
        ) {
            try DatabaseRDFTermCodec.validate(uppercaseLanguageLiteral)
        }
    }

    @Test("bytes-only validation uses one scoped owner borrow")
    func bytesOnlyValidationUsesOneBorrow() throws {
        let term = DatabaseRDFTerm.tripleTerm(
            subject: .iri("urn:subject"),
            predicate: .iri("urn:predicate"),
            object: .literal(DatabaseRDFLiteral(
                lexicalForm: "東京\0event",
                language: try DatabaseRDFLanguageTag("ja")
            ))
        )
        let encoded = try DatabaseRDFTermCodec.encode(term)
        let owner = BorrowCountingOwner(bytes: encoded.contiguousArray())

        try DatabaseRDFTermCodec.validate(
            DatabaseBytes(retaining: owner),
            role: .object
        )

        #expect(owner.borrowCount == 1)
    }

    @Test("streaming output is byte-identical to owned canonical output")
    func streamingOutputMatchesOwnedOutput() throws {
        let term = DatabaseRDFTerm.tripleTerm(
            subject: .blankNode("event"),
            predicate: .iri("urn:calendar:title"),
            object: .literal(DatabaseRDFLiteral(
                lexicalForm: "before\0東京after",
                language: try DatabaseRDFLanguageTag("ja")
            ))
        )
        let plan = try DatabaseRDFTermCodec.encodingPlan(term)
        var sink = CollectingRDFEncodingSink()

        try DatabaseRDFTermCodec.encode(plan, into: &sink)

        let owned = try DatabaseRDFTermCodec.encode(term)
        #expect(plan.byteCount == owned.count)
        #expect(DatabaseBytes(sink.bytes) == owned)
    }

    @Test("validation and semantic decoding reject the same malformed corpus")
    func validationAndDecodingParity() {
        let malformed: [DatabaseBytes] = [
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
        let nested = DatabaseRDFTerm.tripleTerm(
            subject: .iri("urn:subject"),
            predicate: .iri("urn:predicate"),
            object: .iri("urn:object")
        )
        let encoded = try DatabaseRDFTermCodec.encode(nested)

        #expect(
            throws: DatabaseRDFTermCodecError.maximumDepthExceeded(
                actual: 1,
                maximum: 0
            )
        ) {
            try DatabaseRDFTermCodec.validate(
                encoded,
                limits: .init(maximumDepth: 0)
            )
        }
        #expect(
            throws: DatabaseRDFTermCodecError.maximumObjectCountExceeded(
                actual: 4,
                maximum: 3
            )
        ) {
            try DatabaseRDFTermCodec.validate(
                encoded,
                limits: .init(maximumObjectCount: 3)
            )
        }
        #expect(
            throws: DatabaseRDFTermCodecError.maximumBytesExceeded(
                actual: encoded.count,
                maximum: encoded.count - 1
            )
        ) {
            try DatabaseRDFTermCodec.validate(
                encoded,
                limits: .init(maximumBytes: encoded.count - 1)
            )
        }

        var trailing = encoded.copyBytes()
        trailing.append(1)
        #expect(throws: DatabaseRDFTermCodecError.trailingBytes) {
            try DatabaseRDFTermCodec.validate(DatabaseBytes(trailing))
        }
    }

    @Test("nested triple role errors remain exact")
    func nestedTripleRoleErrors() {
        let invalidSubject = DatabaseBytes([
            4,
            3, 2, 0x78, 1, 4, 0x75, 0x3A, 0x74,
            2, 4, 0x75, 0x3A, 0x70,
            2, 4, 0x75, 0x3A, 0x6F,
        ])
        let invalidPredicate = DatabaseBytes([
            4,
            2, 4, 0x75, 0x3A, 0x73,
            1, 2, 0x70,
            2, 4, 0x75, 0x3A, 0x6F,
        ])

        #expect(throws: DatabaseRDFTermCodecError.invalidTripleSubject) {
            try DatabaseRDFTermCodec.validate(invalidSubject)
        }
        #expect(throws: DatabaseRDFTermCodecError.invalidTriplePredicate) {
            try DatabaseRDFTermCodec.validate(invalidPredicate)
        }
    }

    private func validationError(
        for bytes: DatabaseBytes
    ) -> DatabaseRDFTermCodecError? {
        do {
            try DatabaseRDFTermCodec.validate(bytes)
            return nil
        } catch let error {
            return error
        }
    }

    private func decodingError(
        for bytes: DatabaseBytes
    ) -> DatabaseRDFTermCodecError? {
        do {
            _ = try DatabaseRDFTermCodec.decode(bytes)
            return nil
        } catch let error {
            return error
        }
    }
}

private struct CollectingRDFEncodingSink: DatabaseRDFTermEncodingSink {
    var bytes: [UInt8] = []

    mutating func write(_ byte: UInt8) {
        bytes.append(byte)
    }

    mutating func write(_ bytes: UnsafeRawBufferPointer) {
        self.bytes.append(contentsOf: bytes)
    }
}

private final class BorrowCountingOwner: DatabaseByteOwner {
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
