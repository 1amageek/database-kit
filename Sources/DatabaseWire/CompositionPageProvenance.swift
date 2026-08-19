#if DATABASE_KIT_MULTI_BASE
import DatabaseKit
import DatabaseTypes

/// An owner-retaining, ordinal-encoded provenance table for one result page.
public struct CompositionPageProvenance: Sendable {
    private enum Storage: Sendable {
        case materialized([CompositionEncodedOrigin])
        case encoded(ByteString)
    }

    public let composition: CompositionResolution
    public let baseIDs: [Base.ID]
    public let originCount: Int

    private let storage: Storage
    private let limits: DatabaseWireLimits

    public init(
        composition: CompositionResolution,
        origins: [CompositionOrigin]
    ) throws(DatabaseWireError) {
        let baseIDs = composition.bases
        try Self.validateBaseIDs(baseIDs)
        var ordinals: [Base.ID: UInt32] = [:]
        ordinals.reserveCapacity(baseIDs.count)
        for (index, baseID) in baseIDs.enumerated() {
            guard let ordinal = UInt32(exactly: index) else {
                throw .byteCountOverflow
            }
            ordinals[baseID] = ordinal
        }

        var encodedOrigins: [CompositionEncodedOrigin] = []
        encodedOrigins.reserveCapacity(origins.count)
        for origin in origins {
            switch origin {
            case .source(let baseID):
                guard let ordinal = ordinals[baseID] else {
                    throw .invalidCompositionProvenance
                }
                encodedOrigins.append(.source(ordinal))
            case .derived(let contributors):
                try Self.validateContributors(contributors)
                var contributorOrdinals: [UInt32] = []
                contributorOrdinals.reserveCapacity(contributors.count)
                for contributor in contributors {
                    guard let ordinal = ordinals[contributor] else {
                        throw .invalidCompositionProvenance
                    }
                    contributorOrdinals.append(ordinal)
                }
                encodedOrigins.append(.derived(contributorOrdinals))
            }
        }

        self.composition = composition
        self.baseIDs = baseIDs
        self.originCount = origins.count
        self.storage = .materialized(encodedOrigins)
        self.limits = .default
    }

    public func makeOriginIterator() -> CompositionOriginIterator {
        switch storage {
        case .materialized(let origins):
            return CompositionOriginIterator(
                encodedOrigins: origins,
                baseIDs: baseIDs
            )
        case .encoded(let bytes):
            return CompositionOriginIterator(
                encodedOrigins: bytes,
                baseIDs: baseIDs,
                originCount: originCount,
                limits: limits
            )
        }
    }

    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try Self.validateBaseIDs(baseIDs)
        try composition.encode(into: &writer)
        try writer.writeCount(originCount)

        switch storage {
        case .materialized(let origins):
            guard origins.count == originCount else {
                throw .invalidCompositionProvenance
            }
            for origin in origins {
                try Self.encode(
                    origin,
                    baseCount: baseIDs.count,
                    into: &writer
                )
            }
        case .encoded(let bytes):
            var validator = DatabaseWireReader(bytes, limits: writer.limits)
            for _ in 0..<originCount {
                try Self.validateEncodedOrigin(
                    from: &validator,
                    baseCount: baseIDs.count
                )
            }
            try validator.ensureFullyRead()
            writer.writeUnframedBytes(bytes)
        }
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let composition = try CompositionResolution(from: &reader)
        let baseIDs = composition.bases
        let baseCount = baseIDs.count
        try Self.validateBaseIDs(baseIDs)

        let originCount = try reader.readCount()
        let originsStart = reader.consumedByteCount
        for _ in 0..<originCount {
            try Self.validateEncodedOrigin(
                from: &reader,
                baseCount: baseCount
            )
        }
        let originsEnd = reader.consumedByteCount

        self.composition = composition
        self.baseIDs = baseIDs
        self.originCount = originCount
        self.storage = .encoded(
            try reader.bytes(inConsumedRange: originsStart..<originsEnd)
        )
        self.limits = reader.limits
    }

    static func decodeOrigin(
        from reader: inout DatabaseWireReader,
        baseIDs: [Base.ID]
    ) throws(DatabaseWireError) -> CompositionOrigin {
        switch try reader.readUInt8() {
        case 0:
            let ordinal = try reader.readUInt32()
            guard let index = Int(exactly: ordinal), index < baseIDs.count else {
                throw .invalidCompositionProvenance
            }
            return .source(baseIDs[index])
        case 1:
            let count = try reader.readCount()
            guard count > 0 else {
                throw .invalidCompositionProvenance
            }
            var contributors: [Base.ID] = []
            contributors.reserveCapacity(count)
            var previousOrdinal: UInt32?
            for _ in 0..<count {
                let ordinal = try reader.readUInt32()
                guard previousOrdinal.map({ $0 < ordinal }) ?? true,
                      let index = Int(exactly: ordinal),
                      index < baseIDs.count else {
                    throw .invalidCompositionProvenance
                }
                contributors.append(baseIDs[index])
                previousOrdinal = ordinal
            }
            return .derived(contributors: contributors)
        case let tag:
            throw .invalidCompositionOrigin(tag)
        }
    }

    private static func validateBaseIDs(
        _ baseIDs: [Base.ID]
    ) throws(DatabaseWireError) {
        guard !baseIDs.isEmpty else {
            throw .invalidCompositionProvenance
        }
        for (previous, current) in zip(baseIDs, baseIDs.dropFirst()) {
            guard previous < current else {
                throw .invalidCompositionProvenance
            }
        }
    }

    private static func validateContributors(
        _ contributors: [Base.ID]
    ) throws(DatabaseWireError) {
        guard !contributors.isEmpty else {
            throw .invalidCompositionProvenance
        }
        for (previous, current) in zip(
            contributors,
            contributors.dropFirst()
        ) {
            guard previous < current else {
                throw .invalidCompositionProvenance
            }
        }
    }

    private static func encode(
        _ origin: CompositionEncodedOrigin,
        baseCount: Int,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch origin {
        case .source(let ordinal):
            guard Int(ordinal) < baseCount else {
                throw .invalidCompositionProvenance
            }
            writer.writeUInt8(0)
            writer.writeUInt32(ordinal)
        case .derived(let ordinals):
            guard !ordinals.isEmpty else {
                throw .invalidCompositionProvenance
            }
            writer.writeUInt8(1)
            try writer.writeCount(ordinals.count)
            var previousOrdinal: UInt32?
            for ordinal in ordinals {
                guard previousOrdinal.map({ $0 < ordinal }) ?? true,
                      Int(ordinal) < baseCount else {
                    throw .invalidCompositionProvenance
                }
                writer.writeUInt32(ordinal)
                previousOrdinal = ordinal
            }
        }
    }

    private static func validateEncodedOrigin(
        from reader: inout DatabaseWireReader,
        baseCount: Int
    ) throws(DatabaseWireError) {
        switch try reader.readUInt8() {
        case 0:
            guard Int(try reader.readUInt32()) < baseCount else {
                throw .invalidCompositionProvenance
            }
        case 1:
            let count = try reader.readCount()
            guard count > 0 else {
                throw .invalidCompositionProvenance
            }
            var previousOrdinal: UInt32?
            for _ in 0..<count {
                let ordinal = try reader.readUInt32()
                guard previousOrdinal.map({ $0 < ordinal }) ?? true,
                      Int(ordinal) < baseCount else {
                    throw .invalidCompositionProvenance
                }
                previousOrdinal = ordinal
            }
        case let tag:
            throw .invalidCompositionOrigin(tag)
        }
    }

}

#endif
