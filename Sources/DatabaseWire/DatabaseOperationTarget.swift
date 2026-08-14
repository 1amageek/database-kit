#if DATABASE_KIT_MULTIPLE_BASES
import DatabaseKit

/// The logical target selected by an invocation-capable runtime.
public enum DatabaseOperationTarget: Sendable, Hashable {
    case database
    case base(Base.ID)
    case composition(Base.Composition.ID)
}

extension DatabaseOperationTarget: WireValue {
    @_spi(DatabaseExecution)
    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch self {
        case .database:
            writer.writeUInt8(0)
        case .base(let baseID):
            writer.writeUInt8(1)
            try baseID.encode(into: &writer)
        case .composition(let compositionID):
            writer.writeUInt8(2)
            try compositionID.encode(into: &writer)
        }
    }

    @_spi(DatabaseExecution)
    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        switch try reader.readUInt8() {
        case 0:
            self = .database
        case 1:
            self = .base(try Base.ID(from: &reader))
        case 2:
            self = .composition(try Base.Composition.ID(from: &reader))
        case let tag:
            throw .invalidOperationTarget(tag)
        }
    }
}
#endif
