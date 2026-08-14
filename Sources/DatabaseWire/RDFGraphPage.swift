import DatabaseKit
import DatabaseTypes

/// An owner-retaining page of RDF quads.
///
/// Decoding validates each canonical RDF term without constructing the quads,
/// then retains one range of the response frame for on-demand iteration.
public struct RDFGraphPage: Sendable {
    private enum Storage: Sendable {
        case materialized([RDFQuad])
        case encoded(ByteString)
    }

    public let quadCount: Int
    public let continuation: ByteString?
    #if DATABASE_KIT_MULTIPLE_BASES
    public let provenance: CompositionPageProvenance?
    public let consistency: DatabaseReadConsistency
    #else
    public let snapshotVersion: Int64?
    #endif

    private let storage: Storage
    private let limits: DatabaseWireLimits

    var retainedEncodedQuads: ByteString? {
        guard case .encoded(let bytes) = storage else {
            return nil
        }
        return bytes
    }

    #if DATABASE_KIT_MULTIPLE_BASES
    public init(
        quads: consuming [RDFQuad],
        continuation: ByteString? = nil,
        provenance: CompositionPageProvenance?,
        consistency: DatabaseReadConsistency
    ) throws(DatabaseWireError) {
        guard provenance == nil || provenance?.originCount == quads.count else {
            throw .invalidCompositionProvenance
        }
        self.quadCount = quads.count
        self.continuation = continuation
        self.provenance = provenance
        self.consistency = consistency
        self.storage = .materialized(quads)
        self.limits = .default
    }
    #else
    public init(
        quads: consuming [RDFQuad],
        continuation: ByteString? = nil,
        snapshotVersion: Int64? = nil
    ) {
        self.quadCount = quads.count
        self.continuation = continuation
        self.snapshotVersion = snapshotVersion
        self.storage = .materialized(quads)
        self.limits = .default
    }
    #endif

    public func makeQuadIterator() -> RDFQuadIterator {
        switch storage {
        case .materialized(let quads):
            return RDFQuadIterator(quads: quads)
        case .encoded(let bytes):
            return RDFQuadIterator(
                encodedQuads: bytes,
                quadCount: quadCount,
                limits: limits
            )
        }
    }

    public func materializedQuads(
        maximumCount: Int
    ) throws(DatabaseWireError) -> [RDFQuad] {
        guard maximumCount >= 0 else {
            throw .byteCountOverflow
        }
        guard quadCount <= maximumCount else {
            throw .collectionTooLarge(
                actual: quadCount,
                maximum: maximumCount
            )
        }
        var quads: [RDFQuad] = []
        quads.reserveCapacity(quadCount)
        var iterator = makeQuadIterator()
        while let quad = try iterator.next() {
            quads.append(quad)
        }
        return quads
    }

    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeCount(quadCount)
        switch storage {
        case .materialized(let quads):
            for quad in quads {
                try quad.encode(into: &writer)
            }
        case .encoded(let bytes):
            let initialObjectCount = writer.registeredObjectCount
            var validator = DatabaseWireReader(
                bytes,
                limits: writer.limits
            )
            try validator.beginSubtreeValidation(
                nestingDepth: writer.currentNestingDepth,
                registeredObjectCount: initialObjectCount
            )
            for _ in 0..<quadCount {
                try RDFQuad.validateWireRepresentation(from: &validator)
            }
            try validator.ensureFullyRead()
            try writer.registerObjects(
                validator.registeredObjectCount - initialObjectCount
            )
            writer.writeUnframedBytes(bytes)
        }
        #if DATABASE_KIT_MULTIPLE_BASES
        writer.writeBool(provenance != nil)
        if let provenance {
            guard provenance.originCount == quadCount else {
                throw .invalidCompositionProvenance
            }
            try provenance.encode(into: &writer)
        }
        try consistency.encode(into: &writer)
        try writer.writeOptionalBytes(continuation)
        #else
        try writer.writeOptionalBytes(continuation)
        writer.writeBool(snapshotVersion != nil)
        if let snapshotVersion {
            writer.writeInt64(snapshotVersion)
        }
        #endif
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let quadCount = try reader.readCount()
        let quadsStart = reader.consumedByteCount
        for _ in 0..<quadCount {
            try RDFQuad.validateWireRepresentation(from: &reader)
        }
        let quadsEnd = reader.consumedByteCount
        let encodedQuads = try reader.bytes(
            inConsumedRange: quadsStart..<quadsEnd
        )

        self.quadCount = quadCount
        #if DATABASE_KIT_MULTIPLE_BASES
        self.provenance = try reader.readBool()
            ? try CompositionPageProvenance(from: &reader)
            : nil
        guard provenance == nil || provenance?.originCount == quadCount else {
            throw .invalidCompositionProvenance
        }
        self.consistency = try DatabaseReadConsistency(from: &reader)
        self.continuation = try reader.readOptionalBytes()
        #else
        self.continuation = try reader.readOptionalBytes()
        self.snapshotVersion =
            try reader.readBool() ? try reader.readInt64() : nil
        #endif
        self.storage = .encoded(encodedQuads)
        self.limits = reader.limits
    }
}
