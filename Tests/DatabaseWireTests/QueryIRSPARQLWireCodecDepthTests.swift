import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import DatabaseKit
import Testing

@Suite("SPARQL recursive wire codec")
struct QueryIRSPARQLWireCodecDepthTests {
    @Test("SPARQL term tags retain canonical byte order")
    func sparqlTermCanonicalBytesAreStable() throws {
        let literalBytes = ByteString([
            2, 2, 7, 0, 0, 0, 0, 0, 0, 0,
        ])
        #expect(
            try encodeSPARQLTerm(
                .literal(.int(7)),
                limits: .default
            ) == literalBytes
        )

        let triple = SPARQLTerm.tripleTerm(
            subject: .variable("s"),
            predicate: .iri("urn:p"),
            object: .blankNode("o")
        )
        let tripleBytes = ByteString([
            4,
            0, 1, 0, 0, 0, 115,
            1, 5, 0, 0, 0, 117, 114, 110, 58, 112,
            3, 1, 0, 0, 0, 111,
        ])
        #expect(try encodeSPARQLTerm(triple, limits: .default) == tripleBytes)
        #expect(
            try encodeSPARQLTerm(
                decodeSPARQLTerm(tripleBytes, limits: .default),
                limits: .default
            ) == tripleBytes
        )

        let reified = SPARQLTerm.reifiedTriple(
            subject: .variable("s"),
            predicate: .iri("urn:p"),
            object: .blankNode("o"),
            reifier: .variable("r")
        )
        let reifiedBytes = ByteString([
            5,
            0, 1, 0, 0, 0, 115,
            1, 5, 0, 0, 0, 117, 114, 110, 58, 112,
            3, 1, 0, 0, 0, 111,
            0, 1, 0, 0, 0, 114,
        ])
        #expect(try encodeSPARQLTerm(reified, limits: .default) == reifiedBytes)
        #expect(
            try encodeSPARQLTerm(
                decodeSPARQLTerm(reifiedBytes, limits: .default),
                limits: .default
            ) == reifiedBytes
        )
    }

    @Test("property path tags retain canonical byte order")
    func propertyPathCanonicalBytesAreStable() throws {
        let alpha = try RDFPredicateIRI("urn:a")
        let beta = try RDFPredicateIRI("urn:b")
        let exclusions = try PropertyPathNegatedSet(
            forward: Set([beta, alpha]),
            inverse: Set()
        )
        let bounds = try PropertyPathRange(minimum: 2, maximum: 4)
        let path = PropertyPath.range(
            .alternative(
                .sequence(
                    .inverse(.iri(alpha)),
                    .zeroOrMore(.iri(beta))
                ),
                .oneOrMore(
                    .zeroOrOne(.negatedPropertySet(exclusions))
                )
            ),
            bounds
        )
        let expected = ByteString([
            8, 3, 2, 1,
            0, 5, 0, 0, 0, 117, 114, 110, 58, 97,
            4, 0, 5, 0, 0, 0, 117, 114, 110, 58, 98,
            5, 6, 7,
            1, 2, 0, 0, 0,
            5, 0, 0, 0, 117, 114, 110, 58, 97,
            5, 0, 0, 0, 117, 114, 110, 58, 98,
            1, 0, 0, 0, 0,
            2, 0, 0, 0, 0, 0, 0, 0,
            1, 4, 0, 0, 0, 0, 0, 0, 0,
        ])

        #expect(try encodePropertyPath(path, limits: .default) == expected)
        #expect(
            try encodePropertyPath(
                decodePropertyPath(expected, limits: .default),
                limits: .default
            ) == expected
        )
    }

    @Test("SPARQL-star terms traverse depth 320 iteratively")
    func deepSPARQLTermsRoundTripCanonically() throws {
        let limits = try wireLimits(maximumNestingDepth: 512)
        let term = nestedSPARQLTerm(levels: 320)

        let encoded = try encodeSPARQLTerm(term, limits: limits)
        let decoded = try decodeSPARQLTerm(encoded, limits: limits)
        let reencoded = try encodeSPARQLTerm(decoded, limits: limits)

        #expect(reencoded == encoded)
    }

    @Test("SPARQL-star terms enforce the exact maximum depth")
    func deepSPARQLTermsEnforceMaximumDepth() throws {
        let boundedLimits = try wireLimits(maximumNestingDepth: 64)
        let permissiveLimits = try wireLimits(maximumNestingDepth: 512)
        let exact = nestedSPARQLTerm(levels: 63)
        let excessive = nestedSPARQLTerm(levels: 320)
        let excessiveBytes = try encodeSPARQLTerm(
            excessive,
            limits: permissiveLimits
        )
        let expected = DatabaseWireError.nestingTooDeep(
            actual: 65,
            maximum: 64
        )

        let exactBytes = try encodeSPARQLTerm(exact, limits: boundedLimits)
        _ = try decodeSPARQLTerm(exactBytes, limits: boundedLimits)
        #expect(throws: expected) {
            _ = try encodeSPARQLTerm(excessive, limits: boundedLimits)
        }
        #expect(throws: expected) {
            _ = try decodeSPARQLTerm(
                excessiveBytes,
                limits: boundedLimits
            )
        }
    }

    @Test("property paths traverse depth 320 iteratively")
    func deepPropertyPathsRoundTripCanonically() throws {
        let limits = try wireLimits(maximumNestingDepth: 512)
        let path = try nestedPropertyPath(levels: 320)

        let encoded = try encodePropertyPath(path, limits: limits)
        let decoded = try decodePropertyPath(encoded, limits: limits)
        let reencoded = try encodePropertyPath(decoded, limits: limits)

        #expect(reencoded == encoded)
    }

    @Test("property paths enforce the exact maximum depth")
    func deepPropertyPathsEnforceMaximumDepth() throws {
        let boundedLimits = try wireLimits(maximumNestingDepth: 64)
        let permissiveLimits = try wireLimits(maximumNestingDepth: 512)
        let exact = try nestedPropertyPath(levels: 63)
        let excessive = try nestedPropertyPath(levels: 320)
        let excessiveBytes = try encodePropertyPath(
            excessive,
            limits: permissiveLimits
        )
        let expected = DatabaseWireError.nestingTooDeep(
            actual: 65,
            maximum: 64
        )

        let exactBytes = try encodePropertyPath(exact, limits: boundedLimits)
        _ = try decodePropertyPath(exactBytes, limits: boundedLimits)
        #expect(throws: expected) {
            _ = try encodePropertyPath(excessive, limits: boundedLimits)
        }
        #expect(throws: expected) {
            _ = try decodePropertyPath(
                excessiveBytes,
                limits: boundedLimits
            )
        }
    }

    @Test("property path decoding preserves validated invariants")
    func propertyPathDecodeValidationIsPreserved() throws {
        let nonCanonicalSet = ByteString([
            7,
            1, 2, 0, 0, 0,
            5, 0, 0, 0, 117, 114, 110, 58, 98,
            5, 0, 0, 0, 117, 114, 110, 58, 97,
            0,
        ])
        #expect(
            throws: DatabaseWireError.nonCanonicalPropertyPathPredicateSet
        ) {
            _ = try decodePropertyPath(nonCanonicalSet, limits: .default)
        }

        #expect(throws: DatabaseWireError.invalidPropertyPathNegatedSet) {
            _ = try decodePropertyPath([7, 0, 0], limits: .default)
        }

        let invalidRange = ByteString([
            8,
            0, 5, 0, 0, 0, 117, 114, 110, 58, 112,
            3, 0, 0, 0, 0, 0, 0, 0,
            1, 2, 0, 0, 0, 0, 0, 0, 0,
        ])
        #expect(
            throws: DatabaseWireError.invalidPropertyPathRange(
                minimum: 3,
                maximum: 2
            )
        ) {
            _ = try decodePropertyPath(invalidRange, limits: .default)
        }

        let invalidPredicate = ByteString([
            0, 8, 0, 0, 0, 114, 101, 108, 97, 116, 105, 118, 101,
        ])
        #expect(
            throws: DatabaseWireError.invalidRDFPredicateIRI("relative")
        ) {
            _ = try decodePropertyPath(invalidPredicate, limits: .default)
        }
    }

    @Test("SPARQL term IRI validation is preserved at both wire boundaries")
    func sparqlTermIRIValidationIsPreserved() throws {
        #expect(throws: DatabaseWireError.invalidRDFIRI("relative")) {
            _ = try encodeSPARQLTerm(.iri("relative"), limits: .default)
        }

        let invalidIRI = ByteString([
            1, 8, 0, 0, 0, 114, 101, 108, 97, 116, 105, 118, 101,
        ])
        #expect(throws: DatabaseWireError.invalidRDFIRI("relative")) {
            _ = try decodeSPARQLTerm(invalidIRI, limits: .default)
        }
    }

    private func nestedSPARQLTerm(levels: Int) -> SPARQLTerm {
        var term = SPARQLTerm.iri("urn:leaf")
        for level in 0..<levels {
            if level.isMultiple(of: 2) {
                term = .tripleTerm(
                    subject: term,
                    predicate: .iri("urn:predicate"),
                    object: .blankNode("object")
                )
            } else {
                term = .reifiedTriple(
                    subject: term,
                    predicate: .iri("urn:predicate"),
                    object: .blankNode("object"),
                    reifier: .variable("reifier")
                )
            }
        }
        return term
    }

    private func nestedPropertyPath(
        levels: Int
    ) throws -> PropertyPath {
        let alpha = try RDFPredicateIRI("urn:alpha")
        let beta = try RDFPredicateIRI("urn:beta")
        let bounds = try PropertyPathRange(minimum: 1, maximum: 3)
        var path = PropertyPath.iri(alpha)
        for level in 0..<levels {
            switch level % 7 {
            case 0: path = .inverse(path)
            case 1: path = .sequence(path, .iri(beta))
            case 2: path = .alternative(path, .iri(beta))
            case 3: path = .zeroOrMore(path)
            case 4: path = .oneOrMore(path)
            case 5: path = .zeroOrOne(path)
            default: path = .range(path, bounds)
            }
        }
        return path
    }

    private func encodeSPARQLTerm(
        _ term: SPARQLTerm,
        limits: DatabaseWireLimits
    ) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
            try QueryIRWireFormat.encodeSPARQLTerm(term, into: &writer)
        }
    }

    private func decodeSPARQLTerm(
        _ bytes: ByteString,
        limits: DatabaseWireLimits
    ) throws(DatabaseWireError) -> SPARQLTerm {
        var reader = DatabaseWireReader(bytes, limits: limits)
        let term = try QueryIRWireFormat.decodeSPARQLTerm(from: &reader)
        try reader.ensureFullyRead()
        return term
    }

    private func encodePropertyPath(
        _ path: PropertyPath,
        limits: DatabaseWireLimits
    ) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
            try QueryIRWireFormat.encodePropertyPath(path, into: &writer)
        }
    }

    private func decodePropertyPath(
        _ bytes: ByteString,
        limits: DatabaseWireLimits
    ) throws(DatabaseWireError) -> PropertyPath {
        var reader = DatabaseWireReader(bytes, limits: limits)
        let path = try QueryIRWireFormat.decodePropertyPath(from: &reader)
        try reader.ensureFullyRead()
        return path
    }

    private func wireLimits(
        maximumNestingDepth: Int
    ) throws -> DatabaseWireLimits {
        try DatabaseWireLimits(
            maximumFrameBytes: 64 * 1_024,
            maximumStringBytes: 1_024,
            maximumByteStringBytes: 64 * 1_024,
            maximumCollectionCount: 1_024,
            maximumNestingDepth: maximumNestingDepth,
            maximumObjectCount: 4_096
        )
    }
}
