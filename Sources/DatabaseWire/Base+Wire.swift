#if DATABASE_KIT_MULTIPLE_BASES
import DatabaseKit

extension Base.ID: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeString(value)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let value = try reader.readString()
        do {
            try self.init(value)
        } catch let error {
            throw .invalidBaseIdentifier(error)
        }
    }
}

extension Base.Placement.ID: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeString(value)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let value = try reader.readString()
        do {
            try self.init(value)
        } catch let error {
            throw .invalidBaseIdentifier(error)
        }
    }
}

extension Base.Composition.ID: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeString(value)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let value = try reader.readString()
        do {
            try self.init(value)
        } catch let error {
            throw .invalidBaseIdentifier(error)
        }
    }
}

extension Base.Composition: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
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
        try id.encode(into: &writer)
        try writer.writeCount(bases.count)
        for baseID in bases {
            try baseID.encode(into: &writer)
        }
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let id = try Base.Composition.ID(from: &reader)
        let count = try reader.readCount()
        var bases: [Base.ID] = []
        bases.reserveCapacity(count)
        for _ in 0..<count {
            bases.append(try Base.ID(from: &reader))
        }
        do {
            try self.init(id: id, bases: bases)
        } catch let error {
            throw .invalidBaseComposition(error)
        }
        guard self.bases == bases else {
            throw .invalidBaseComposition(.nonCanonicalBaseOrder)
        }
    }
}

#endif
