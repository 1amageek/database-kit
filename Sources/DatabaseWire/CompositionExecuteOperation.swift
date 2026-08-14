#if DATABASE_KIT_MULTIPLE_BASES
import DatabaseKit

public enum CompositionExecuteOperation: DatabaseOperationDeclaration {
    public static let identifier =
        DatabaseOperationIdentifier.compositionExecute

    public struct Description: Sendable, Hashable {
        public let composition: Base.Composition
        public let revision: UInt64
        public let generation: UInt64

        public init(
            composition: Base.Composition,
            revision: UInt64,
            generation: UInt64
        ) {
            self.composition = composition
            self.revision = revision
            self.generation = generation
        }

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try composition.encode(into: &writer)
            writer.writeUInt64(revision)
            writer.writeUInt64(generation)
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                composition: try Base.Composition(from: &reader),
                revision: try reader.readUInt64(),
                generation: try reader.readUInt64()
            )
        }
    }

    public struct MutationResult: Sendable, Hashable {
        public let revision: UInt64
        public let generation: UInt64

        public init(revision: UInt64, generation: UInt64) {
            self.revision = revision
            self.generation = generation
        }

        fileprivate func encode(
            into writer: inout DatabaseWireWriter
        ) {
            writer.writeUInt64(revision)
            writer.writeUInt64(generation)
        }

        fileprivate init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                revision: try reader.readUInt64(),
                generation: try reader.readUInt64()
            )
        }
    }

    public enum Invocation: Sendable, Hashable {
        case list
        case describe
        case create(
            composition: Base.Composition,
            expectedRevision: UInt64,
            idempotencyKey: String
        )
        case replace(
            bases: [Base.ID],
            expectedRevision: UInt64,
            idempotencyKey: String
        )
        case delete(expectedRevision: UInt64, idempotencyKey: String)
    }

    public struct Request: WireValue, Hashable {
        public let invocation: Invocation

        public init(invocation: Invocation) {
            self.invocation = invocation
        }

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch invocation {
            case .list:
                writer.writeUInt8(0)
            case .describe:
                writer.writeUInt8(1)
            case .create(
                let composition,
                let expectedRevision,
                let idempotencyKey
            ):
                writer.writeUInt8(2)
                try composition.encode(into: &writer)
                writer.writeUInt64(expectedRevision)
                try Self.encodeIdempotencyKey(idempotencyKey, into: &writer)
            case .replace(
                let bases,
                let expectedRevision,
                let idempotencyKey
            ):
                writer.writeUInt8(3)
                try Self.encodeCanonicalBases(bases, into: &writer)
                writer.writeUInt64(expectedRevision)
                try Self.encodeIdempotencyKey(idempotencyKey, into: &writer)
            case .delete(let expectedRevision, let idempotencyKey):
                writer.writeUInt8(4)
                writer.writeUInt64(expectedRevision)
                try Self.encodeIdempotencyKey(idempotencyKey, into: &writer)
            }
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 0:
                self.init(invocation: .list)
            case 1:
                self.init(invocation: .describe)
            case 2:
                self.init(
                    invocation: .create(
                        composition: try Base.Composition(from: &reader),
                        expectedRevision: try reader.readUInt64(),
                        idempotencyKey: try Self.decodeIdempotencyKey(
                            from: &reader
                        )
                    )
                )
            case 3:
                self.init(
                    invocation: .replace(
                        bases: try Self.decodeCanonicalBases(from: &reader),
                        expectedRevision: try reader.readUInt64(),
                        idempotencyKey: try Self.decodeIdempotencyKey(
                            from: &reader
                        )
                    )
                )
            case 4:
                self.init(
                    invocation: .delete(
                        expectedRevision: try reader.readUInt64(),
                        idempotencyKey: try Self.decodeIdempotencyKey(
                            from: &reader
                        )
                    )
                )
            case let tag:
                throw .invalidCompositionExecutionInvocation(tag)
            }
        }

        private static func encodeCanonicalBases(
            _ bases: [Base.ID],
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try validateCanonicalBases(bases)
            try writer.writeCount(bases.count)
            for baseID in bases {
                try baseID.encode(into: &writer)
            }
        }

        private static func decodeCanonicalBases(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> [Base.ID] {
            let count = try reader.readCount()
            var bases: [Base.ID] = []
            bases.reserveCapacity(count)
            for _ in 0..<count {
                bases.append(try Base.ID(from: &reader))
            }
            try validateCanonicalBases(bases)
            return bases
        }

        private static func validateCanonicalBases(
            _ bases: [Base.ID]
        ) throws(DatabaseWireError) {
            guard !bases.isEmpty else {
                throw .invalidBaseComposition(.empty)
            }
            for (previous, current) in zip(bases, bases.dropFirst()) {
                guard previous < current else {
                    if previous == current {
                        throw .invalidBaseComposition(
                            .duplicateBase(current)
                        )
                    }
                    throw .invalidBaseComposition(.nonCanonicalBaseOrder)
                }
            }
        }

        private static func encodeIdempotencyKey(
            _ idempotencyKey: String,
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            guard !idempotencyKey.isEmpty else {
                throw .emptyIdempotencyKey
            }
            try writer.writeString(idempotencyKey)
        }

        private static func decodeIdempotencyKey(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) -> String {
            let idempotencyKey = try reader.readString()
            guard !idempotencyKey.isEmpty else {
                throw .emptyIdempotencyKey
            }
            return idempotencyKey
        }
    }

    public enum Response: WireValue, Hashable {
        case compositions([Description])
        case composition(Description)
        case mutation(MutationResult)

        func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            switch self {
            case .compositions(let compositions):
                try Self.validateCanonical(compositions)
                writer.writeUInt8(0)
                try writer.writeCount(compositions.count)
                for composition in compositions {
                    try composition.encode(into: &writer)
                }
            case .composition(let composition):
                writer.writeUInt8(1)
                try composition.encode(into: &writer)
            case .mutation(let mutation):
                writer.writeUInt8(2)
                mutation.encode(into: &writer)
            }
        }

        init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try reader.readUInt8() {
            case 0:
                let count = try reader.readCount()
                var compositions: [Description] = []
                compositions.reserveCapacity(count)
                for _ in 0..<count {
                    compositions.append(try Description(from: &reader))
                }
                try Self.validateCanonical(compositions)
                self = .compositions(compositions)
            case 1:
                self = .composition(try Description(from: &reader))
            case 2:
                self = .mutation(try MutationResult(from: &reader))
            case let tag:
                throw .invalidCompositionExecutionResponse(tag)
            }
        }

        private static func validateCanonical(
            _ compositions: [Description]
        ) throws(DatabaseWireError) {
            for (previous, current) in zip(
                compositions,
                compositions.dropFirst()
            ) {
                guard previous.composition.id < current.composition.id else {
                    throw .nonCanonicalCompositionSet
                }
            }
        }
    }
}

#endif
