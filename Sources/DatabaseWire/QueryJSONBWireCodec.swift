import DatabaseKit
import DatabaseTypes

/// Traverses one JSONB tree with one bounded frame per open collection.
enum QueryJSONBWireCodec {
    private struct EncodingFrame {
        let node: QueryJSONBNode
        var nextIndex: Int
    }

    static func encode(_ root: QueryJSONBNode, into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        var frames: [EncodingFrame] = []
        var next: QueryJSONBNode? = root
        var open = 0
        defer { writer.abandonNestedValues(open) }
        while next != nil || !frames.isEmpty {
            if let node = next {
                next = nil
                try writer.beginNestedValue()
                open += 1
                switch node {
                case .null: writer.writeUInt8(0)
                case .bool(let value): writer.writeUInt8(1); writer.writeBool(value)
                case .string(let value): writer.writeUInt8(2); try writer.writeString(value)
                case .number(let value): writer.writeUInt8(3); QueryValueWireCodec.encodeNumeric(value, into: &writer)
                case .array(let values):
                    writer.writeUInt8(4)
                    try writer.writeCount(values.count)
                    frames.append(EncodingFrame(node: node, nextIndex: 0))
                    continue
                case .object(let members):
                    writer.writeUInt8(5)
                    try writer.writeCount(members.count)
                    frames.append(EncodingFrame(node: node, nextIndex: 0))
                    continue
                }
                try writer.endNestedValue()
                open -= 1
                continue
            }
            let index = frames.count - 1
            let childIndex = frames[index].nextIndex
            switch frames[index].node {
            case .array(let values) where childIndex < values.count:
                frames[index].nextIndex += 1
                next = values[childIndex]
            case .object(let members) where childIndex < members.count:
                frames[index].nextIndex += 1
                try writer.writeString(members[childIndex].key)
                next = members[childIndex].value
            default:
                frames.removeLast()
                try writer.endNestedValue()
                open -= 1
            }
        }
    }

    static func decode(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> QueryJSONBValue {
        guard let root = try traverse(from: &reader, materialize: true) else { throw .invalidQueryIRWireState }
        try reader.registerQueryJSONBStorage(root.storageFootprint)
        do throws(QueryValueError) { return try QueryJSONBValue(root: root, limits: reader.queryValueLimits) }
        catch let error { throw .invalidQueryValue(error) }
    }

    static func validate(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        _ = try traverse(from: &reader, materialize: false)
    }

    private struct DecodingFrame {
        let isObject: Bool
        var remaining: Int
        var values: [Int] = []
        var members: [QueryJSONBIndexedMember] = []
        var previousKey: ByteString?
        var pendingKey: String?
    }

    private static func traverse(from reader: inout DatabaseWireReader, materialize: Bool) throws(DatabaseWireError) -> QueryJSONBNode? {
        var frames: [DecodingFrame] = []
        var builder = QueryJSONBBuilder(limits: reader.queryValueLimits)
        var open = 0
        defer { reader.abandonNestedValues(open) }
        while true {
            if let frame = frames.last, frame.isObject {
                let bytes = try reader.validateQueryStringBytes()
                try validateString(bytes)
                if let previous = frame.previousKey, !precedes(previous, bytes) {
                    throw .invalidQueryValue(.nonCanonicalJSONB)
                }
                let index = frames.count - 1
                frames[index].previousKey = bytes
                if materialize {
                    guard let key = DatabaseWireTextDecoder.decode(bytes) else { throw .invalidUTF8 }
                    frames[index].pendingKey = key
                }
            }
            try reader.beginNestedValue()
            open += 1
            var completed: Int?
            let tag = try reader.readUInt8()
            switch tag {
            case 0: if materialize { completed = try append(.null, to: &builder) }
            case 1:
                let value = try reader.readBool()
                if materialize { completed = try append(.bool(value), to: &builder) }
            case 2:
                let bytes = try reader.validateQueryStringBytes()
                try validateString(bytes)
                if materialize {
                    guard let value = DatabaseWireTextDecoder.decode(bytes) else { throw .invalidUTF8 }
                    completed = try append(.string(value), to: &builder)
                }
            case 3:
                let value = try QueryValueWireCodec.decodeNumeric(from: &reader)
                if materialize { completed = try append(.number(value), to: &builder) }
            case 4, 5:
                let isObject = tag == 5
                let count = try reader.readCount()
                if count > 0 {
                    frames.append(DecodingFrame(isObject: isObject, remaining: count))
                    continue
                }
                if materialize { completed = try appendCollection(DecodingFrame(isObject: isObject, remaining: 0), to: &builder) }
            case let tag: throw .invalidValueTag(tag)
            }
            try reader.endNestedValue()
            open -= 1
            while true {
                guard !frames.isEmpty else {
                    guard materialize, let root = completed else { return nil }
                    do throws(QueryValueError) { return try builder.finish(root: root) }
                    catch let error { throw .invalidQueryValue(error) }
                }
                let index = frames.count - 1
                if materialize {
                    guard let value = completed else { throw .invalidQueryIRWireState }
                    if frames[index].isObject {
                        guard let key = frames[index].pendingKey else { throw .invalidQueryIRWireState }
                        frames[index].members.append(QueryJSONBIndexedMember(key: key, value: value))
                        frames[index].pendingKey = nil
                    } else { frames[index].values.append(value) }
                }
                frames[index].remaining -= 1
                if frames[index].remaining > 0 { break }
                let frame = frames.removeLast()
                if materialize { completed = try appendCollection(frame, to: &builder) }
                try reader.endNestedValue()
                open -= 1
            }
        }
    }

    private static func append(_ scalar: QueryJSONBNode, to builder: inout QueryJSONBBuilder) throws(DatabaseWireError) -> Int {
        do throws(QueryValueError) { return try builder.append(scalar) }
        catch let error { throw .invalidQueryValue(error) }
    }

    private static func appendCollection(_ frame: DecodingFrame, to builder: inout QueryJSONBBuilder) throws(DatabaseWireError) -> Int {
        do throws(QueryValueError) {
            return try frame.isObject ? builder.appendObject(frame.members) : builder.appendArray(frame.values)
        } catch let error { throw .invalidQueryValue(error) }
    }

    private static func validateString(_ bytes: ByteString) throws(DatabaseWireError) {
        guard !bytes.contains(0) else { throw .invalidQueryValue(.nonCanonicalJSONB) }
    }

    private static func precedes(_ lhs: ByteString, _ rhs: ByteString) -> Bool {
        if lhs.count != rhs.count { return lhs.count < rhs.count }
        return lhs.lexicographicallyPrecedes(rhs)
    }
}
