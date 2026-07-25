import DatabaseKit
import DatabaseTypes

extension SHACLPath: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        var pending: [EncodingStep] = [.path(self)]
        var openNestedValueCount = 0
        defer { writer.abandonNestedValues(openNestedValueCount) }

        while let step = pending.popLast() {
            switch step {
            case .path(let path):
                try writer.beginNestedValue()
                openNestedValueCount += 1
                pending.append(.endNestedValue)
                switch path {
                case .predicate(let iri):
                    writer.writeUInt8(1)
                    try writer.writeString(iri.rawValue)
                case .inverse(let inner):
                    writer.writeUInt8(2)
                    pending.append(.path(inner))
                case .sequence(let paths):
                    writer.writeUInt8(3)
                    try writer.writeCount(paths.elements.count)
                    pending.append(.list(paths.elements, nextIndex: 0))
                case .alternative(let paths):
                    writer.writeUInt8(4)
                    try writer.writeCount(paths.elements.count)
                    pending.append(.list(paths.elements, nextIndex: 0))
                case .zeroOrMore(let inner):
                    writer.writeUInt8(5)
                    pending.append(.path(inner))
                case .oneOrMore(let inner):
                    writer.writeUInt8(6)
                    pending.append(.path(inner))
                case .zeroOrOne(let inner):
                    writer.writeUInt8(7)
                    pending.append(.path(inner))
                }

            case .list(let paths, let nextIndex):
                guard nextIndex < paths.count else { continue }
                pending.append(.list(paths, nextIndex: nextIndex + 1))
                pending.append(.path(paths[nextIndex]))

            case .endNestedValue:
                guard openNestedValueCount > 0 else {
                    throw .invalidSHACLPathWireState
                }
                try writer.endNestedValue()
                openNestedValueCount -= 1
            }
        }
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        var frames: [DecodingFrame] = []
        var openNestedValueCount = 0
        defer { reader.abandonNestedValues(openNestedValueCount) }

        while true {
            try reader.beginNestedValue()
            openNestedValueCount += 1

            let tag = try reader.readUInt8()
            switch tag {
            case 1:
                let rawIRI = try reader.readString()
                let predicate: RDFPredicateIRI
                do {
                    predicate = try RDFPredicateIRI(rawIRI)
                } catch {
                    throw .invalidRDFPredicateIRI(rawIRI)
                }
                var completed = SHACLPath.predicate(predicate)
                try reader.endNestedValue()
                openNestedValueCount -= 1
                if let root = try Self.finish(
                    completed: &completed,
                    frames: &frames,
                    reader: &reader,
                    openNestedValueCount: &openNestedValueCount
                ) {
                    self = root
                    return
                }

            case 2, 5, 6, 7:
                frames.append(.unary(tag: tag))

            case 3, 4:
                let count = try reader.readCount()
                guard count >= 2 else {
                    throw .invalidSHACLPath(
                        .insufficientMembers(actual: count)
                    )
                }
                frames.append(.list(tag: tag, count: count))

            case let invalidTag:
                throw .invalidValueTag(invalidTag)
            }
        }
    }

    static func validateWireRepresentation(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        var frames: [ValidationFrame] = []
        var openNestedValueCount = 0
        defer { reader.abandonNestedValues(openNestedValueCount) }

        while true {
            try reader.beginNestedValue()
            openNestedValueCount += 1

            switch try reader.readUInt8() {
            case 1:
                let rawIRI = try reader.readString()
                do {
                    _ = try RDFPredicateIRI(rawIRI)
                } catch {
                    throw .invalidRDFPredicateIRI(rawIRI)
                }
                try reader.endNestedValue()
                openNestedValueCount -= 1

                var needsNextChild = false
                while let frame = frames.popLast() {
                    switch frame {
                    case .unary:
                        try reader.endNestedValue()
                        openNestedValueCount -= 1

                    case .list(let remaining):
                        if remaining > 1 {
                            frames.append(.list(remaining: remaining - 1))
                            needsNextChild = true
                            break
                        }
                        try reader.endNestedValue()
                        openNestedValueCount -= 1
                    }
                    if needsNextChild { break }
                }
                if !needsNextChild {
                    return
                }

            case 2, 5, 6, 7:
                frames.append(.unary)

            case 3, 4:
                let count = try reader.readCount()
                guard count >= 2 else {
                    throw .invalidSHACLPath(
                        .insufficientMembers(actual: count)
                    )
                }
                frames.append(.list(remaining: count))

            case let invalidTag:
                throw .invalidValueTag(invalidTag)
            }
        }
    }
}

private extension SHACLPath {
    enum EncodingStep {
        case path(SHACLPath)
        case list([SHACLPath], nextIndex: Int)
        case endNestedValue
    }

    enum DecodingFrame {
        case unary(tag: UInt8)
        case list(
            tag: UInt8,
            count: Int,
            elements: [SHACLPath] = []
        )
    }

    enum ValidationFrame {
        case unary
        case list(remaining: Int)
    }

    static func finish(
        completed: inout SHACLPath,
        frames: inout [DecodingFrame],
        reader: inout DatabaseWireReader,
        openNestedValueCount: inout Int
    ) throws(DatabaseWireError) -> SHACLPath? {
        while let frame = frames.popLast() {
            switch frame {
            case .unary(let tag):
                switch tag {
                case 2:
                    completed = .inverse(completed)
                case 5:
                    completed = .zeroOrMore(completed)
                case 6:
                    completed = .oneOrMore(completed)
                case 7:
                    completed = .zeroOrOne(completed)
                default:
                    throw .invalidSHACLPathWireState
                }
                try reader.endNestedValue()
                openNestedValueCount -= 1

            case .list(let tag, let count, var elements):
                elements.append(completed)
                if elements.count < count {
                    frames.append(
                        .list(tag: tag, count: count, elements: consume elements)
                    )
                    return nil
                }
                guard elements.count == count else {
                    throw .invalidSHACLPathWireState
                }
                let list: SHACLPathList
                do {
                    list = try SHACLPathList(consume elements)
                } catch let error {
                    throw .invalidSHACLPath(error)
                }
                switch tag {
                case 3:
                    completed = .sequence(list)
                case 4:
                    completed = .alternative(list)
                default:
                    throw .invalidSHACLPathWireState
                }
                try reader.endNestedValue()
                openNestedValueCount -= 1
            }
        }
        return completed
    }
}
