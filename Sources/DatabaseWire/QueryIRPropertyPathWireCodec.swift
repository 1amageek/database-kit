import DatabaseValue
import QueryIR

/// Encodes and decodes recursive property paths without process-stack recursion.
enum QueryIRPropertyPathWireCodec {
    static func encode(
        _ path: PropertyPath,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        var encodingSteps: [EncodingStep] = [.path(path)]
        var openNestedValueCount = 0
        defer {
            while openNestedValueCount > 0 {
                writer.endNestedValue()
                openNestedValueCount -= 1
            }
        }

        while let encodingStep = encodingSteps.popLast() {
            switch consume encodingStep {
            case .path(let value):
                try writer.beginNestedValue()
                openNestedValueCount += 1
                encodingSteps.append(.endNestedValue)
                try encodeContents(value, into: &writer, encodingSteps: &encodingSteps)

            case .binaryCursor(let children, let nextIndex):
                guard nextIndex < 2,
                      let child = children.child(at: nextIndex) else {
                    throw .invalidQueryIRWireState
                }
                if nextIndex == 0 {
                    encodingSteps.append(
                        .binaryCursor(children, nextIndex: 1)
                    )
                }
                encodingSteps.append(.path(child))

            case .rangeBounds(let bounds):
                try QueryIRWireCodec.writeInt(
                    bounds.minimum,
                    into: &writer
                )
                try QueryIRWireCodec.writeOptionalInt(
                    bounds.maximum,
                    into: &writer
                )

            case .endNestedValue:
                guard openNestedValueCount > 0 else {
                    throw .invalidQueryIRWireState
                }
                writer.endNestedValue()
                openNestedValueCount -= 1
            }
        }

        guard openNestedValueCount == 0 else {
            throw .invalidQueryIRWireState
        }
    }

    static func decode(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> PropertyPath {
        var frames: [AssemblyFrame] = []
        var openNestedValueCount = 0
        defer {
            while openNestedValueCount > 0 {
                reader.endNestedValue()
                openNestedValueCount -= 1
            }
        }

        while true {
            try reader.beginNestedValue()
            openNestedValueCount += 1
            let tag = try reader.readUInt8()
            switch tag {
            case 1:
                frames.append(.unary(.inverse))
                continue
            case 2:
                frames.append(.binary(.sequence, lhs: nil))
                continue
            case 3:
                frames.append(.binary(.alternative, lhs: nil))
                continue
            case 4:
                frames.append(.unary(.zeroOrMore))
                continue
            case 5:
                frames.append(.unary(.oneOrMore))
                continue
            case 6:
                frames.append(.unary(.zeroOrOne))
                continue
            case 8:
                frames.append(.range)
                continue
            default:
                break
            }

            var completed = try decodeScalar(tag: tag, from: &reader)
            reader.endNestedValue()
            openNestedValueCount -= 1

            var needsNextChild = false
            while let frame = frames.popLast() {
                switch consume frame {
                case .unary(let kind):
                    completed = kind.build(completed)
                    reader.endNestedValue()
                    openNestedValueCount -= 1

                case .binary(let kind, .none):
                    frames.append(.binary(kind, lhs: completed))
                    needsNextChild = true

                case .binary(let kind, .some(let lhs)):
                    completed = kind.build(lhs: lhs, rhs: completed)
                    reader.endNestedValue()
                    openNestedValueCount -= 1

                case .range:
                    let minimum = try QueryIRWireCodec.readInt(
                        from: &reader
                    )
                    let maximum = try QueryIRWireCodec.readOptionalInt(
                        from: &reader
                    )
                    completed = .range(
                        completed,
                        try validatedRange(
                            minimum: minimum,
                            maximum: maximum
                        )
                    )
                    reader.endNestedValue()
                    openNestedValueCount -= 1
                }
                if needsNextChild { break }
            }

            if needsNextChild { continue }
            guard frames.isEmpty, openNestedValueCount == 0 else {
                throw .invalidQueryIRWireState
            }
            return completed
        }
    }
}

private extension QueryIRPropertyPathWireCodec {
    enum EncodingStep {
        case path(PropertyPath)
        case binaryCursor(BinaryChildren, nextIndex: Int)
        case rangeBounds(PropertyPathRange)
        case endNestedValue
    }

    struct BinaryChildren {
        let lhs: PropertyPath
        let rhs: PropertyPath

        func child(at index: Int) -> PropertyPath? {
            switch index {
            case 0: return lhs
            case 1: return rhs
            default: return nil
            }
        }
    }

    enum UnaryKind {
        case inverse
        case zeroOrMore
        case oneOrMore
        case zeroOrOne

        func build(_ path: consuming PropertyPath) -> PropertyPath {
            switch self {
            case .inverse: return .inverse(path)
            case .zeroOrMore: return .zeroOrMore(path)
            case .oneOrMore: return .oneOrMore(path)
            case .zeroOrOne: return .zeroOrOne(path)
            }
        }
    }

    enum BinaryKind {
        case sequence
        case alternative

        func build(
            lhs: consuming PropertyPath,
            rhs: consuming PropertyPath
        ) -> PropertyPath {
            switch self {
            case .sequence: return .sequence(lhs, rhs)
            case .alternative: return .alternative(lhs, rhs)
            }
        }
    }

    enum AssemblyFrame {
        case unary(UnaryKind)
        case binary(BinaryKind, lhs: PropertyPath?)
        case range
    }

    static func encodeContents(
        _ path: consuming PropertyPath,
        into writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        switch consume path {
        case .iri(let value):
            writer.writeUInt8(0)
            try writer.writeString(value.rawValue)
        case .inverse(let child):
            writer.writeUInt8(1)
            encodingSteps.append(.path(child))
        case .sequence(let lhs, let rhs):
            writer.writeUInt8(2)
            encodingSteps.append(
                .binaryCursor(
                    BinaryChildren(lhs: lhs, rhs: rhs),
                    nextIndex: 0
                )
            )
        case .alternative(let lhs, let rhs):
            writer.writeUInt8(3)
            encodingSteps.append(
                .binaryCursor(
                    BinaryChildren(lhs: lhs, rhs: rhs),
                    nextIndex: 0
                )
            )
        case .zeroOrMore(let child):
            writer.writeUInt8(4)
            encodingSteps.append(.path(child))
        case .oneOrMore(let child):
            writer.writeUInt8(5)
            encodingSteps.append(.path(child))
        case .zeroOrOne(let child):
            writer.writeUInt8(6)
            encodingSteps.append(.path(child))
        case .negatedPropertySet(let exclusions):
            writer.writeUInt8(7)
            try writeOptionalPredicateIRIs(
                exclusions.forward,
                into: &writer
            )
            try writeOptionalPredicateIRIs(
                exclusions.inverse,
                into: &writer
            )
        case .range(let child, let bounds):
            writer.writeUInt8(8)
            encodingSteps.append(.rangeBounds(bounds))
            encodingSteps.append(.path(child))
        }
    }

    static func decodeScalar(
        tag: UInt8,
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> PropertyPath {
        switch tag {
        case 0:
            return .iri(try readPredicateIRI(from: &reader))
        case 7:
            let forward = try readOptionalPredicateIRIs(from: &reader)
            let inverse = try readOptionalPredicateIRIs(from: &reader)
            do {
                return .negatedPropertySet(
                    try PropertyPathNegatedSet(
                        forward: forward,
                        inverse: inverse
                    )
                )
            } catch {
                throw .invalidPropertyPathNegatedSet
            }
        default:
            throw .invalidValueTag(tag)
        }
    }

    static func validatedRange(
        minimum: Int,
        maximum: Int?
    ) throws(DatabaseWireError) -> PropertyPathRange {
        do {
            return try PropertyPathRange(
                minimum: minimum,
                maximum: maximum
            )
        } catch {
            throw .invalidPropertyPathRange(
                minimum: minimum,
                maximum: maximum
            )
        }
    }

    static func writeOptionalPredicateIRIs(
        _ values: Set<DatabaseRDFPredicateIRI>?,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        guard let values else {
            writer.writeBool(false)
            return
        }
        writer.writeBool(true)
        let orderedValues = values.sorted()
        try writer.writeCount(orderedValues.count)
        for value in orderedValues {
            try writer.writeString(value.rawValue)
        }
    }

    static func readOptionalPredicateIRIs(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> Set<DatabaseRDFPredicateIRI>? {
        guard try reader.readBool() else { return nil }
        let count = try reader.readCount()
        var result = Set<DatabaseRDFPredicateIRI>()
        result.reserveCapacity(count)
        var previous: DatabaseRDFPredicateIRI?

        for _ in 0..<count {
            let predicate = try readPredicateIRI(from: &reader)
            if let previous, !(previous < predicate) {
                throw .nonCanonicalPropertyPathPredicateSet
            }
            result.insert(predicate)
            previous = predicate
        }
        return result
    }

    static func readPredicateIRI(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> DatabaseRDFPredicateIRI {
        let value = try reader.readString()
        do {
            return try DatabaseRDFPredicateIRI(value)
        } catch {
            throw .invalidRDFPredicateIRI(value)
        }
    }
}
