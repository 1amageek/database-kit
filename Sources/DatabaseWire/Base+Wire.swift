#if DATABASE_KIT_MULTI_BASE
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

extension CompositionSelection: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch kind {
        case .named:
            guard let namedID, bases == nil else {
                throw .invalidCompositionProvenance
            }
            writer.writeUInt8(0)
            try namedID.encode(into: &writer)
        case .derived:
            guard namedID == nil, let bases else {
                throw .invalidCompositionProvenance
            }
            writer.writeUInt8(1)
            try writer.writeCount(bases.count)
            for baseID in bases {
                try baseID.encode(into: &writer)
            }
        }
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        switch try reader.readUInt8() {
        case 0:
            self = .named(try Base.Composition.ID(from: &reader))
        case 1:
            let count = try reader.readCount()
            var bases: [Base.ID] = []
            bases.reserveCapacity(count)
            for _ in 0..<count {
                bases.append(try Base.ID(from: &reader))
            }
            do { self = try .derived(bases) }
            catch let error { throw .invalidBaseComposition(error) }
            guard self.bases == bases else {
                throw .invalidBaseComposition(.nonCanonicalBaseOrder)
            }
        case let tag:
            throw .invalidOperationTarget(tag)
        }
    }
}

extension CompositionResolution: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch kind {
        case .named:
            guard let namedID, let generation else {
                throw .invalidCompositionProvenance
            }
            writer.writeUInt8(0)
            try namedID.encode(into: &writer)
            writer.writeUInt64(generation)
        case .derived:
            guard namedID == nil, generation == nil else {
                throw .invalidCompositionProvenance
            }
            writer.writeUInt8(1)
        }
        try writer.writeCount(bases.count)
        for baseID in bases {
            try baseID.encode(into: &writer)
        }
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let tag = try reader.readUInt8()
        let namedID: Base.Composition.ID?
        let generation: UInt64?
        switch tag {
        case 0:
            namedID = try Base.Composition.ID(from: &reader)
            generation = try reader.readUInt64()
        case 1:
            namedID = nil
            generation = nil
        default:
            throw .invalidCompositionProvenance
        }
        let count = try reader.readCount()
        var bases: [Base.ID] = []
        bases.reserveCapacity(count)
        for _ in 0..<count {
            bases.append(try Base.ID(from: &reader))
        }
        do {
            if let namedID, let generation {
                self = try .named(
                    id: namedID,
                    generation: generation,
                    bases: bases
                )
            } else {
                self = try .derived(bases)
            }
        } catch let error {
            throw .invalidBaseComposition(error)
        }
    }
}

#endif
