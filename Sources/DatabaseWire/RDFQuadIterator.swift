import DatabaseKit
import DatabaseTypes

/// A single-pass iterator that materializes RDF quads on demand.
public struct RDFQuadIterator: Sendable {
    private enum Storage: Sendable {
        case materialized(quads: [RDFQuad], nextIndex: Int)
        case encoded(reader: DatabaseWireReader, remaining: Int)
    }

    private var storage: Storage

    init(quads: [RDFQuad]) {
        storage = .materialized(
            quads: quads,
            nextIndex: quads.startIndex
        )
    }

    init(
        encodedQuads: ByteString,
        quadCount: Int,
        limits: DatabaseWireLimits
    ) {
        storage = .encoded(
            reader: DatabaseWireReader(encodedQuads, limits: limits),
            remaining: quadCount
        )
    }

    public mutating func next()
        throws(DatabaseWireError) -> RDFQuad? {
        switch storage {
        case .materialized(let quads, let nextIndex):
            guard nextIndex < quads.endIndex else {
                return nil
            }
            storage = .materialized(
                quads: quads,
                nextIndex: nextIndex + 1
            )
            return quads[nextIndex]

        case .encoded(var reader, let remaining):
            guard remaining > 0 else {
                try reader.ensureFullyRead()
                return nil
            }
            let quad = try RDFQuad(from: &reader)
            let nextRemaining = remaining - 1
            if nextRemaining == 0 {
                try reader.ensureFullyRead()
            }
            storage = .encoded(
                reader: reader,
                remaining: nextRemaining
            )
            return quad
        }
    }
}
