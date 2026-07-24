import DatabaseTypes
import QueryIR

/// Encodes and decodes recursive label expressions without process-stack recursion.
enum QueryIRLabelExpressionWireCodec {
    static func encode(
        _ expression: LabelExpression,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        var encodingSteps: [EncodingStep] = [.expression(expression)]
        var openNestedValueCount = 0
        defer {
            while openNestedValueCount > 0 {
                writer.endNestedValue()
                openNestedValueCount -= 1
            }
        }

        while let encodingStep = encodingSteps.popLast() {
            switch consume encodingStep {
            case .expression(let value):
                try writer.beginNestedValue()
                openNestedValueCount += 1
                encodingSteps.append(.endNestedValue)
                try encodeContents(value, into: &writer, encodingSteps: &encodingSteps)

            case .collectionCursor(let values, let nextIndex):
                guard nextIndex < values.count else { continue }
                encodingSteps.append(
                    .collectionCursor(values, nextIndex: nextIndex + 1)
                )
                encodingSteps.append(.expression(values[nextIndex]))

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
    ) throws(DatabaseWireError) -> LabelExpression {
        var frames: [CollectionFrame] = []
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

            if tag == 2 || tag == 3 {
                let elementCount = try reader.readCount()
                if elementCount > 0 {
                    frames.append(
                        CollectionFrame(tag: tag, elementCount: elementCount)
                    )
                    continue
                }
            }

            var completed = try decodeLeafOrEmptyCollection(
                tag: tag,
                from: &reader
            )
            reader.endNestedValue()
            openNestedValueCount -= 1

            while true {
                guard !frames.isEmpty else { return completed }
                let frameIndex = frames.index(before: frames.endIndex)
                guard frames[frameIndex].nextIndex
                        < frames[frameIndex].elementCount else {
                    throw .invalidQueryIRWireState
                }

                frames[frameIndex].elements.append(completed)
                frames[frameIndex].nextIndex += 1
                if frames[frameIndex].nextIndex
                    < frames[frameIndex].elementCount {
                    break
                }

                let frame = frames.removeLast()
                reader.endNestedValue()
                openNestedValueCount -= 1
                completed = try frame.assemble()
            }
        }
    }
}

private extension QueryIRLabelExpressionWireCodec {
    enum EncodingStep {
        case expression(LabelExpression)
        case collectionCursor([LabelExpression], nextIndex: Int)
        case endNestedValue
    }

    struct CollectionFrame {
        let tag: UInt8
        let elementCount: Int
        var nextIndex: Int
        var elements: [LabelExpression]

        init(tag: UInt8, elementCount: Int) {
            self.tag = tag
            self.elementCount = elementCount
            self.nextIndex = 0
            self.elements = []
            self.elements.reserveCapacity(elementCount)
        }

        consuming func assemble() throws(DatabaseWireError) -> LabelExpression {
            switch tag {
            case 2:
                return .or(elements)
            case 3:
                return .and(elements)
            default:
                throw .invalidQueryIRWireState
            }
        }
    }

    static func encodeContents(
        _ expression: consuming LabelExpression,
        into writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        switch consume expression {
        case .single(let value):
            writer.writeUInt8(0)
            try writer.writeString(value)
        case .column(let value):
            writer.writeUInt8(1)
            try writer.writeString(value)
        case .or(let values):
            writer.writeUInt8(2)
            try writer.writeCount(values.count)
            if !values.isEmpty {
                encodingSteps.append(.collectionCursor(values, nextIndex: 0))
            }
        case .and(let values):
            writer.writeUInt8(3)
            try writer.writeCount(values.count)
            if !values.isEmpty {
                encodingSteps.append(.collectionCursor(values, nextIndex: 0))
            }
        }
    }

    static func decodeLeafOrEmptyCollection(
        tag: UInt8,
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> LabelExpression {
        switch tag {
        case 0:
            return .single(try reader.readString())
        case 1:
            return .column(try reader.readString())
        case 2:
            return .or([])
        case 3:
            return .and([])
        default:
            throw .invalidValueTag(tag)
        }
    }
}
