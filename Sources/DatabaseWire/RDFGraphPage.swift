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
    public let snapshotVersion: Int64?

    private let storage: Storage
    private let limits: DatabaseWireLimits

    var retainedEncodedQuads: ByteString? {
        guard case .encoded(let bytes) = storage else {
            return nil
        }
        return bytes
    }

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
        try writer.writeOptionalBytes(continuation)
        writer.writeBool(snapshotVersion != nil)
        if let snapshotVersion {
            writer.writeInt64(snapshotVersion)
        }
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
        self.continuation = try reader.readOptionalBytes()
        self.snapshotVersion =
            try reader.readBool() ? try reader.readInt64() : nil
        self.storage = .encoded(encodedQuads)
        self.limits = reader.limits
    }
}
