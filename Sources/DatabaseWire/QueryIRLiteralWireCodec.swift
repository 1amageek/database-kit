import DatabaseTypes
import DatabaseKit

/// Encodes and decodes recursive literal arrays without process-stack recursion.
enum QueryIRLiteralWireCodec {
    static func encode(
        _ literal: Literal,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        var encodingSteps: [EncodingStep] = [.literal(literal)]
        var openNestedValueCount = 0
        defer { writer.abandonNestedValues(openNestedValueCount) }

        while let encodingStep = encodingSteps.popLast() {
            switch consume encodingStep {
            case .literal(let value):
                try writer.beginNestedValue()
                openNestedValueCount += 1
                encodingSteps.append(.endNestedValue)
                try encodeContents(value, into: &writer, encodingSteps: &encodingSteps)

            case .arrayCursor(let values, let nextIndex):
                guard nextIndex < values.count else { continue }
                encodingSteps.append(
                    .arrayCursor(values, nextIndex: nextIndex + 1)
                )
                encodingSteps.append(.literal(values[nextIndex]))

            case .endNestedValue:
                guard openNestedValueCount > 0 else {
                    throw .invalidQueryIRWireState
                }
                try writer.endNestedValue()
                openNestedValueCount -= 1
            }
        }

        guard openNestedValueCount == 0 else {
            throw .invalidQueryIRWireState
        }
    }

    static func decode(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> Literal {
        var frames: [ArrayFrame] = []
        var openNestedValueCount = 0
        defer { reader.abandonNestedValues(openNestedValueCount) }

        while true {
            try reader.beginNestedValue()
            openNestedValueCount += 1
            let tag = try reader.readUInt8()

            if tag == 8 {
                let elementCount = try reader.readCount()
                if elementCount > 0 {
                    frames.append(ArrayFrame(elementCount: elementCount))
                    continue
                }
            }

            var completed = try decodeScalarOrEmptyArray(
                tag: tag,
                from: &reader
            )
            try reader.endNestedValue()
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
                try reader.endNestedValue()
                openNestedValueCount -= 1
                completed = .array(frame.elements)
            }
        }
    }
}

private extension QueryIRLiteralWireCodec {
    enum EncodingStep {
        case literal(Literal)
        case arrayCursor([Literal], nextIndex: Int)
        case endNestedValue
    }

    struct ArrayFrame {
        let elementCount: Int
        var nextIndex: Int
        var elements: [Literal]

        init(elementCount: Int) {
            self.elementCount = elementCount
            self.nextIndex = 0
            self.elements = []
            self.elements.reserveCapacity(elementCount)
        }
    }

    static func encodeContents(
        _ literal: consuming Literal,
        into writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        switch consume literal {
        case .null:
            writer.writeUInt8(0)
        case .bool(let value):
            writer.writeUInt8(1)
            writer.writeBool(value)
        case .int(let value):
            writer.writeUInt8(2)
            writer.writeInt64(value)
        case .double(let value):
            writer.writeUInt8(3)
            writer.writeDouble(value)
        case .string(let value):
            writer.writeUInt8(4)
            try writer.writeString(value)
        case .date(let value):
            writer.writeUInt8(5)
            writer.writeInt32(value.year)
            writer.writeUInt8(value.month)
            writer.writeUInt8(value.day)
        case .timestamp(let value):
            writer.writeUInt8(6)
            writer.writeInt64(value.secondsSinceUnixEpoch)
            writer.writeUInt32(value.nanoseconds)
        case .binary(let value):
            writer.writeUInt8(7)
            try writer.writeBytes(value)
        case .array(let values):
            writer.writeUInt8(8)
            try writer.writeCount(values.count)
            encodingSteps.append(.arrayCursor(values, nextIndex: 0))
        case .iri(let value):
            writer.writeUInt8(9)
            try QueryIRWireFormat.writeSPARQLIRI(value, into: &writer)
        case .blankNode(let value):
            writer.writeUInt8(10)
            try writer.writeString(value)
        case .typedLiteral(let value, let datatype):
            writer.writeUInt8(11)
            try writer.writeString(value)
            try QueryIRWireFormat.writeRDFDatatypeIRI(datatype, into: &writer)
        case .langLiteral(let value, let language):
            writer.writeUInt8(12)
            try writer.writeString(value)
            try QueryIRWireFormat.writeRDFLanguageTag(language, into: &writer)
        case .dirLangLiteral(let value, let language, let direction):
            writer.writeUInt8(13)
            try writer.writeString(value)
            try QueryIRWireFormat.writeRDFLanguageTag(language, into: &writer)
            try QueryIRWireFormat.writeRDFDirection(direction, into: &writer)
        case .uuid(let value):
            writer.writeUInt8(14)
            writer.writeUInt64(value.high)
            writer.writeUInt64(value.low)
        case .uint(let value):
            writer.writeUInt8(15)
            writer.writeUInt64(value)
        case .decimal(let value):
            writer.writeUInt8(16)
            writer.writeInt128(value.coefficient)
            writer.writeInt32(value.scale)
        case .rdfTerm(let term):
            writer.writeUInt8(17)
            try term.encode(into: &writer)
        }
    }

    static func decodeScalarOrEmptyArray(
        tag: UInt8,
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> Literal {
        switch tag {
        case 0:
            return .null
        case 1:
            return .bool(try reader.readBool())
        case 2:
            return .int(try reader.readInt64())
        case 3:
            return .double(try reader.readDouble())
        case 4:
            return .string(try reader.readString())
        case 5:
            let year = try reader.readInt32()
            let month = try reader.readUInt8()
            let day = try reader.readUInt8()
            do {
                return .date(
                    try CivilDate(year: year, month: month, day: day)
                )
            } catch let error {
                throw .invalidCivilDate(error)
            }
        case 6:
            let seconds = try reader.readInt64()
            let nanoseconds = try reader.readUInt32()
            do {
                return .timestamp(
                    try Timestamp(
                        secondsSinceUnixEpoch: seconds,
                        nanoseconds: nanoseconds
                    )
                )
            } catch {
                throw .invalidTimestamp
            }
        case 7:
            return .binary(try reader.readBytes())
        case 8:
            return .array([])
        case 9:
            return .iri(try QueryIRWireFormat.readSPARQLIRI(from: &reader))
        case 10:
            return .blankNode(try reader.readString())
        case 11:
            return .typedLiteral(
                value: try reader.readString(),
                datatype: try QueryIRWireFormat.readRDFDatatypeIRI(from: &reader)
            )
        case 12:
            return .langLiteral(
                value: try reader.readString(),
                language: try QueryIRWireFormat.readRDFLanguageTag(from: &reader)
            )
        case 13:
            return .dirLangLiteral(
                value: try reader.readString(),
                language: try QueryIRWireFormat.readRDFLanguageTag(from: &reader),
                direction: try QueryIRWireFormat.readRDFDirection(from: &reader)
            )
        case 14:
            return .uuid(
                DatabaseTypes.UUID(
                    high: try reader.readUInt64(),
                    low: try reader.readUInt64()
                )
            )
        case 15:
            return .uint(try reader.readUInt64())
        case 16:
            return .decimal(
                ExactDecimal(
                    coefficient: try reader.readInt128(),
                    scale: try reader.readInt32()
                )
            )
        case 17:
            return .rdfTerm(try RDFTerm(from: &reader))
        default:
            throw .invalidValueTag(tag)
        }
    }
}
