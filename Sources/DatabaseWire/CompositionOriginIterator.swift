#if DATABASE_KIT_MULTIPLE_BASES
import DatabaseKit
import DatabaseTypes

enum CompositionEncodedOrigin: Sendable {
    case source(UInt32)
    case derived([UInt32])
}

/// Iterates Composition origins without materializing a complete result page.
public struct CompositionOriginIterator {
    private enum Storage {
        case materialized(
            origins: [CompositionEncodedOrigin],
            baseIDs: [Base.ID],
            index: Int
        )
        case encoded(
            reader: DatabaseWireReader,
            baseIDs: [Base.ID],
            remainingCount: Int
        )
    }

    private var storage: Storage

    init(
        encodedOrigins: [CompositionEncodedOrigin],
        baseIDs: [Base.ID]
    ) {
        self.storage = .materialized(
            origins: encodedOrigins,
            baseIDs: baseIDs,
            index: 0
        )
    }

    init(
        encodedOrigins: ByteString,
        baseIDs: [Base.ID],
        originCount: Int,
        limits: DatabaseWireLimits
    ) {
        self.storage = .encoded(
            reader: DatabaseWireReader(encodedOrigins, limits: limits),
            baseIDs: baseIDs,
            remainingCount: originCount
        )
    }

    public mutating func next() throws(DatabaseWireError) -> CompositionOrigin? {
        switch storage {
        case .materialized(let origins, let baseIDs, let index):
            guard index < origins.count else {
                return nil
            }
            storage = .materialized(
                origins: origins,
                baseIDs: baseIDs,
                index: index + 1
            )
            switch origins[index] {
            case .source(let ordinal):
                return .source(baseIDs[Int(ordinal)])
            case .derived(let ordinals):
                var contributors: [Base.ID] = []
                contributors.reserveCapacity(ordinals.count)
                for ordinal in ordinals {
                    contributors.append(baseIDs[Int(ordinal)])
                }
                return .derived(contributors: contributors)
            }
        case .encoded(var reader, let baseIDs, let remainingCount):
            guard remainingCount > 0 else {
                try reader.ensureFullyRead()
                return nil
            }
            let origin = try CompositionPageProvenance.decodeOrigin(
                from: &reader,
                baseIDs: baseIDs
            )
            storage = .encoded(
                reader: reader,
                baseIDs: baseIDs,
                remainingCount: remainingCount - 1
            )
            return origin
        }
    }
}

#endif
