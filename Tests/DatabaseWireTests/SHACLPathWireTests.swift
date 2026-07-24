import DatabaseKit
import DatabaseTypes
import DatabaseWire
import Testing

@Suite("SHACL path wire")
struct SHACLPathWireTests {
    @Test("compound paths round-trip canonically")
    func compoundPathRoundTrip() throws {
        let path = SHACLPath.sequence(
            try SHACLPathList([
                .predicate(try RDFPredicateIRI("urn:parent")),
                .alternative(
                    try SHACLPathList([
                        .predicate(try RDFPredicateIRI("urn:name")),
                        .inverse(
                            .predicate(
                                try RDFPredicateIRI("urn:label")
                            )
                        ),
                    ])
                ),
            ])
        )

        let encoded = try DatabaseEnvelopeCodec.encode(path)
        let decoded = try DatabaseEnvelopeCodec.decode(
            SHACLPath.self,
            from: encoded
        )

        #expect(decoded == path)
        #expect(try DatabaseEnvelopeCodec.encode(decoded) == encoded)
    }

    @Test("sequence and alternative paths require two members")
    func pathListCardinalityIsValidated() throws {
        let bytes = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writer.withNestedValue {
                (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                writer.writeUInt8(3)
                try writer.writeCount(1)
                try writer.withNestedValue {
                    (writer: inout DatabaseWireWriter)
                        throws(DatabaseWireError) in
                    writer.writeUInt8(1)
                    try writer.writeString("urn:only")
                }
            }
        }

        #expect(
            throws: DatabaseWireError.invalidSHACLPath(
                .insufficientMembers(actual: 1)
            )
        ) {
            _ = try DatabaseEnvelopeCodec.decode(
                SHACLPath.self,
                from: bytes
            )
        }
    }

    @Test("deep paths use iterative wire traversal")
    func deepPathsRoundTripIteratively() throws {
        let limits = try wireLimits(maximumNestingDepth: 512)
        let path = try nestedPath(levels: 320)

        let encoded = try DatabaseEnvelopeCodec.encode(path, limits: limits)
        let decoded = try DatabaseEnvelopeCodec.decode(
            SHACLPath.self,
            from: encoded,
            limits: limits
        )

        #expect(
            try DatabaseEnvelopeCodec.encode(decoded, limits: limits)
                == encoded
        )
    }

    @Test("path nesting obeys the exact configured limit")
    func nestingLimitIsExact() throws {
        let boundedLimits = try wireLimits(maximumNestingDepth: 64)
        let permissiveLimits = try wireLimits(maximumNestingDepth: 512)
        let exact = try nestedPath(levels: 63)
        let excessive = try nestedPath(levels: 320)
        let excessiveBytes = try DatabaseEnvelopeCodec.encode(
            excessive,
            limits: permissiveLimits
        )
        let expected = DatabaseWireError.nestingTooDeep(
            actual: 65,
            maximum: 64
        )

        let exactBytes = try DatabaseEnvelopeCodec.encode(
            exact,
            limits: boundedLimits
        )
        _ = try DatabaseEnvelopeCodec.decode(
            SHACLPath.self,
            from: exactBytes,
            limits: boundedLimits
        )
        #expect(throws: expected) {
            _ = try DatabaseEnvelopeCodec.encode(
                excessive,
                limits: boundedLimits
            )
        }
        #expect(throws: expected) {
            _ = try DatabaseEnvelopeCodec.decode(
                SHACLPath.self,
                from: excessiveBytes,
                limits: boundedLimits
            )
        }
    }

    private func nestedPath(levels: Int) throws -> SHACLPath {
        var path = SHACLPath.predicate(try RDFPredicateIRI("urn:leaf"))
        for _ in 0..<levels {
            path = .inverse(path)
        }
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
