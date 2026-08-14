#if DATABASE_KIT_MULTIPLE_BASES
/// A stable logical boundary for data, authorization, provenance, placement,
/// and transactions.
public struct Base: Sendable, Hashable {
    public struct ID: Sendable, Hashable, Comparable {
        public static let maximumUTF8ByteCount = 128

        public let value: String

        public init(_ value: String) throws(BaseIdentifierError) {
            try Self.validate(value)
            self.value = value
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.value < rhs.value
        }

        private static func validate(
            _ value: String
        ) throws(BaseIdentifierError) {
            let bytes = value.utf8
            guard !bytes.isEmpty,
                  bytes.count <= maximumUTF8ByteCount else {
                throw .invalidUTF8ByteCount(
                    actual: bytes.count,
                    maximum: maximumUTF8ByteCount
                )
            }

            var segmentStart = true
            var previousWasHyphen = false
            for (offset, byte) in bytes.enumerated() {
                switch byte {
                case 0x61...0x7a, 0x30...0x39:
                    segmentStart = false
                    previousWasHyphen = false
                case 0x2d:
                    guard !segmentStart else {
                        throw .invalidSegmentBoundary(
                            byte: byte,
                            offset: offset
                        )
                    }
                    previousWasHyphen = true
                case 0x2e:
                    guard !segmentStart else {
                        throw .emptySegment(offset: offset)
                    }
                    guard !previousWasHyphen else {
                        throw .invalidSegmentBoundary(
                            byte: 0x2d,
                            offset: offset - 1
                        )
                    }
                    segmentStart = true
                    previousWasHyphen = false
                default:
                    throw .invalidCharacter(byte: byte, offset: offset)
                }
            }

            guard !segmentStart else {
                throw .emptySegment(offset: bytes.count)
            }
            guard !previousWasHyphen else {
                throw .invalidSegmentBoundary(
                    byte: 0x2d,
                    offset: bytes.count - 1
                )
            }
        }
    }

    public struct Placement: Sendable, Hashable {
        public struct ID: Sendable, Hashable, Comparable {
            public let value: String

            public init(_ value: String) throws(BaseIdentifierError) {
                _ = try Base.ID(value)
                self.value = value
            }

            public static func < (lhs: Self, rhs: Self) -> Bool {
                lhs.value < rhs.value
            }
        }

        public let id: ID

        public init(id: ID) {
            self.id = id
        }
    }

    public struct Composition: Sendable, Hashable {
        public struct ID: Sendable, Hashable, Comparable {
            public let value: String

            public init(_ value: String) throws(BaseIdentifierError) {
                _ = try Base.ID(value)
                self.value = value
            }

            public static func < (lhs: Self, rhs: Self) -> Bool {
                lhs.value < rhs.value
            }
        }

        public let id: ID
        public let bases: [Base.ID]

        public init(
            id: ID,
            bases: [Base.ID]
        ) throws(BaseCompositionError) {
            guard !bases.isEmpty else {
                throw .empty
            }
            let canonicalBases = bases.sorted()
            for (previous, current) in zip(
                canonicalBases,
                canonicalBases.dropFirst()
            ) {
                guard previous != current else {
                    throw .duplicateBase(current)
                }
            }
            self.id = id
            self.bases = canonicalBases
        }

        init(
            canonicalID id: ID,
            bases: [Base.ID]
        ) throws(BaseCompositionError) {
            try self.init(id: id, bases: bases)
            guard self.bases == bases else {
                throw .nonCanonicalBaseOrder
            }
        }
    }

    public let id: ID

    public init(id: ID) {
        self.id = id
    }
}

#endif
