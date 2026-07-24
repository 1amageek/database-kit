import DatabaseTypes
import DatabaseKit

/// Encodes and decodes recursive SPARQL-star terms without process-stack recursion.
enum QueryIRSPARQLTermWireCodec {
    static func encode(
        _ term: SPARQLTerm,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        var encodingSteps: [EncodingStep] = [.term(term)]
        var openNestedValueCount = 0
        defer {
            while openNestedValueCount > 0 {
                writer.endNestedValue()
                openNestedValueCount -= 1
            }
        }

        while let encodingStep = encodingSteps.popLast() {
            switch consume encodingStep {
            case .term(let value):
                try writer.beginNestedValue()
                openNestedValueCount += 1
                encodingSteps.append(.endNestedValue)
                try encodeContents(value, into: &writer, encodingSteps: &encodingSteps)

            case .childCursor(let children, let nextIndex):
                guard nextIndex < children.count,
                      let child = children.child(at: nextIndex) else {
                    throw .invalidQueryIRWireState
                }
                if nextIndex + 1 < children.count {
                    encodingSteps.append(
                        .childCursor(
                            children,
                            nextIndex: nextIndex + 1
                        )
                    )
                }
                encodingSteps.append(.term(child))

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
    ) throws(DatabaseWireError) -> SPARQLTerm {
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
            case 4:
                frames.append(AssemblyFrame(kind: .triple))
                continue
            case 5:
                frames.append(AssemblyFrame(kind: .reifiedTriple))
                continue
            default:
                break
            }

            var completed = try decodeScalar(tag: tag, from: &reader)
            reader.endNestedValue()
            openNestedValueCount -= 1

            while !frames.isEmpty {
                var frame = frames.removeLast()
                guard let assembled = try frame.append(completed) else {
                    frames.append(frame)
                    break
                }
                reader.endNestedValue()
                openNestedValueCount -= 1
                completed = assembled
            }

            if frames.isEmpty {
                guard openNestedValueCount == 0 else {
                    throw .invalidQueryIRWireState
                }
                return completed
            }
        }
    }
}

private extension QueryIRSPARQLTermWireCodec {
    enum EncodingStep {
        case term(SPARQLTerm)
        case childCursor(TermChildren, nextIndex: Int)
        case endNestedValue
    }

    struct TermChildren {
        let subject: SPARQLTerm
        let predicate: SPARQLTerm
        let object: SPARQLTerm
        let reifier: SPARQLTerm?

        var count: Int {
            if case .some = reifier { return 4 }
            return 3
        }

        func child(at index: Int) -> SPARQLTerm? {
            switch index {
            case 0: return subject
            case 1: return predicate
            case 2: return object
            case 3: return reifier
            default: return nil
            }
        }
    }

    enum AssemblyKind {
        case triple
        case reifiedTriple

        var childCount: Int {
            switch self {
            case .triple: 3
            case .reifiedTriple: 4
            }
        }
    }

    struct AssemblyFrame {
        let kind: AssemblyKind
        var nextIndex = 0
        var subject: SPARQLTerm?
        var predicate: SPARQLTerm?
        var object: SPARQLTerm?
        var reifier: SPARQLTerm?

        mutating func append(
            _ term: consuming SPARQLTerm
        ) throws(DatabaseWireError) -> SPARQLTerm? {
            guard nextIndex < kind.childCount else {
                throw .invalidQueryIRWireState
            }
            switch nextIndex {
            case 0:
                subject = term
            case 1:
                predicate = term
            case 2:
                object = term
            case 3:
                reifier = term
            default:
                throw .invalidQueryIRWireState
            }
            nextIndex += 1

            guard nextIndex == kind.childCount else { return nil }
            guard let subject, let predicate, let object else {
                throw .invalidQueryIRWireState
            }
            switch kind {
            case .triple:
                return .tripleTerm(
                    subject: subject,
                    predicate: predicate,
                    object: object
                )
            case .reifiedTriple:
                guard let reifier else {
                    throw .invalidQueryIRWireState
                }
                return .reifiedTriple(
                    subject: subject,
                    predicate: predicate,
                    object: object,
                    reifier: reifier
                )
            }
        }
    }

    static func encodeContents(
        _ term: consuming SPARQLTerm,
        into writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        switch consume term {
        case .variable(let value):
            writer.writeUInt8(0)
            try QueryIRWireCodec.writeSPARQLVariableName(
                value,
                into: &writer
            )
        case .iri(let value):
            writer.writeUInt8(1)
            try QueryIRWireCodec.writeSPARQLIRI(value, into: &writer)
        case .literal(let value):
            writer.writeUInt8(2)
            try QueryIRWireCodec.encodeLiteral(value, into: &writer)
        case .blankNode(let value):
            writer.writeUInt8(3)
            try writer.writeString(value)
        case .tripleTerm(let subject, let predicate, let object):
            writer.writeUInt8(4)
            encodingSteps.append(
                .childCursor(
                    TermChildren(
                        subject: subject,
                        predicate: predicate,
                        object: object,
                        reifier: nil
                    ),
                    nextIndex: 0
                )
            )
        case .reifiedTriple(
            let subject,
            let predicate,
            let object,
            let reifier
        ):
            writer.writeUInt8(5)
            encodingSteps.append(
                .childCursor(
                    TermChildren(
                        subject: subject,
                        predicate: predicate,
                        object: object,
                        reifier: reifier
                    ),
                    nextIndex: 0
                )
            )
        }
    }

    static func decodeScalar(
        tag: UInt8,
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SPARQLTerm {
        switch tag {
        case 0:
            return .variable(
                try QueryIRWireCodec.readSPARQLVariableName(from: &reader)
            )
        case 1:
            return .iri(
                try QueryIRWireCodec.readSPARQLIRI(from: &reader)
            )
        case 2:
            return .literal(
                try QueryIRWireCodec.decodeLiteral(from: &reader)
            )
        case 3:
            return .blankNode(try reader.readString())
        default:
            throw .invalidValueTag(tag)
        }
    }
}
