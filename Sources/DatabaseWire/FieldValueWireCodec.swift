import DatabaseTypes
import DatabaseValue

/// Iteratively encodes and decodes recursive primitive values.
///
/// Open arrays, objects, references, and composite identifiers are represented
/// by explicit frames so adversarial input cannot grow the process stack.
enum FieldValueWireCodec {
    static func encode(
        _ value: FieldValue,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encode(.value(value), into: &writer)
    }

    static func encode(
        _ object: FieldObject,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        let fields = object.fields
        try writer.writeCount(fields.count)
        for field in fields {
            try writer.writeString(field.key)
            try encode(field.value, into: &writer)
        }
    }

    static func encode(
        _ reference: EntityReference,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encode(
            .reference(reference, closesValue: false),
            into: &writer
        )
    }

    static func decodeValue(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> FieldValue {
        switch try decode(.value, from: &reader) {
        case .value(let value):
            return value
        case .objectField, .identifier, .reference:
            preconditionFailure("Field value decoder produced the wrong root type")
        }
    }

    static func decodeObject(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> FieldObject {
        let count = try reader.readCount()
        var fields: [(key: String, value: FieldValue)] = []
        fields.reserveCapacity(count)
        for _ in 0..<count {
            fields.append(
                (
                    key: try reader.readString(),
                    value: try decodeValue(from: &reader)
                )
            )
        }
        return try canonicalObject(fields)
    }

    static func decodeReference(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> EntityReference {
        switch try decode(.reference, from: &reader) {
        case .reference(let reference):
            return reference
        case .value, .objectField, .identifier:
            preconditionFailure("Entity reference decoder produced the wrong root type")
        }
    }
}

private extension FieldValueWireCodec {
    typealias ObjectField = (key: String, value: FieldValue)

    enum EncodingNode {
        case value(FieldValue)
        case objectField(ObjectField)
        case identifier(ReferenceIdentifier)
        case reference(EntityReference, closesValue: Bool)
    }

    enum EncodingFrame {
        case array([FieldValue], nextIndex: Int)
        case object([ObjectField], nextIndex: Int)
        case identifierComposite([ReferenceIdentifier], nextIndex: Int)
        case referenceIdentifier(EntityReference, closesValue: Bool)
        case referencePartitions(
            EntityReference,
            fields: [ObjectField],
            nextIndex: Int,
            closesValue: Bool
        )
    }

    static func encode(
        _ root: EncodingNode,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        var frames: [EncodingFrame] = []
        var nextNode: EncodingNode? = root
        var openValueCount = 0

        defer {
            while openValueCount > 0 {
                writer.endNestedValue()
                openValueCount -= 1
            }
        }

        while nextNode != nil || !frames.isEmpty {
            if let node = nextNode {
                nextNode = nil
                switch node {
                case .value(let value):
                    try writer.beginNestedValue()
                    openValueCount += 1

                    switch value {
                    case .null:
                        writer.writeUInt8(0)
                    case .bool(let value):
                        writer.writeUInt8(1)
                        writer.writeBool(value)
                    case .int8(let value):
                        writer.writeUInt8(2)
                        writer.writeInt8(value)
                    case .int16(let value):
                        writer.writeUInt8(3)
                        writer.writeInt16(value)
                    case .int32(let value):
                        writer.writeUInt8(4)
                        writer.writeInt32(value)
                    case .int64(let value):
                        writer.writeUInt8(5)
                        writer.writeInt64(value)
                    case .uint8(let value):
                        writer.writeUInt8(6)
                        writer.writeUInt8(value)
                    case .uint16(let value):
                        writer.writeUInt8(7)
                        writer.writeUInt16(value)
                    case .uint32(let value):
                        writer.writeUInt8(8)
                        writer.writeUInt32(value)
                    case .uint64(let value):
                        writer.writeUInt8(9)
                        writer.writeUInt64(value)
                    case .float32(let value):
                        writer.writeUInt8(10)
                        writer.writeFloat(value)
                    case .float64(let value):
                        writer.writeUInt8(11)
                        writer.writeDouble(value)
                    case .decimal(let value):
                        writer.writeUInt8(12)
                        writer.writeInt128(value.coefficient)
                        writer.writeInt32(value.scale)
                    case .string(let value):
                        writer.writeUInt8(13)
                        try writer.writeString(value)
                    case .bytes(let value):
                        writer.writeUInt8(14)
                        try writer.writeBytes(value)
                    case .date(let value):
                        writer.writeUInt8(15)
                        writer.writeInt32(value.year)
                        writer.writeUInt8(value.month)
                        writer.writeUInt8(value.day)
                    case .time(let value):
                        writer.writeUInt8(16)
                        writer.writeUInt8(value.hour)
                        writer.writeUInt8(value.minute)
                        writer.writeUInt8(value.second)
                        writer.writeUInt32(value.nanoseconds)
                    case .dateTime(let value):
                        writer.writeUInt8(17)
                        writer.writeInt32(value.date.year)
                        writer.writeUInt8(value.date.month)
                        writer.writeUInt8(value.date.day)
                        writer.writeUInt8(value.time.hour)
                        writer.writeUInt8(value.time.minute)
                        writer.writeUInt8(value.time.second)
                        writer.writeUInt32(value.time.nanoseconds)
                    case .timestamp(let value):
                        writer.writeUInt8(18)
                        writer.writeInt64(value.secondsSinceUnixEpoch)
                        writer.writeUInt32(value.nanoseconds)
                    case .timeSpan(let value):
                        writer.writeUInt8(19)
                        writer.writeInt64(value.seconds)
                        writer.writeUInt32(value.nanoseconds)
                    case .calendarPeriod(let value):
                        writer.writeUInt8(20)
                        writer.writeInt64(value.months)
                        writer.writeInt64(value.days)
                    case .geographicPoint(let value):
                        writer.writeUInt8(21)
                        writer.writeDouble(value.latitude)
                        writer.writeDouble(value.longitude)
                    case .geographicPosition(let value):
                        writer.writeUInt8(22)
                        writer.writeDouble(value.point.latitude)
                        writer.writeDouble(value.point.longitude)
                        writer.writeDouble(value.ellipsoidalHeightInMeters)
                    case .vector(let value):
                        writer.writeUInt8(23)
                        try encodeVector(value, into: &writer)
                    case .uuid(let value):
                        writer.writeUInt8(24)
                        writer.writeUInt64(value.high)
                        writer.writeUInt64(value.low)
                    case .array(let values):
                        writer.writeUInt8(25)
                        try writer.writeCount(values.count)
                        frames.append(.array(values, nextIndex: 0))
                        continue
                    case .object(let object):
                        writer.writeUInt8(26)
                        let fields = object.fields
                        try writer.writeCount(fields.count)
                        frames.append(.object(fields, nextIndex: 0))
                        continue
                    case .reference(let reference):
                        writer.writeUInt8(27)
                        nextNode = .reference(reference, closesValue: true)
                        continue
                    case .rdfTerm(let term):
                        writer.writeUInt8(28)
                        try writer.writeCanonicalRDFTerm(term)
                    }

                    writer.endNestedValue()
                    openValueCount -= 1

                case .objectField(let field):
                    try writer.writeString(field.key)
                    nextNode = .value(field.value)

                case .identifier(let identifier):
                    try writer.beginNestedValue()
                    openValueCount += 1
                    switch identifier {
                    case .bool(let value):
                        writer.writeUInt8(0)
                        writer.writeBool(value)
                    case .int8(let value):
                        writer.writeUInt8(1)
                        writer.writeInt8(value)
                    case .int16(let value):
                        writer.writeUInt8(2)
                        writer.writeInt16(value)
                    case .int32(let value):
                        writer.writeUInt8(3)
                        writer.writeInt32(value)
                    case .int64(let value):
                        writer.writeUInt8(4)
                        writer.writeInt64(value)
                    case .uint8(let value):
                        writer.writeUInt8(5)
                        writer.writeUInt8(value)
                    case .uint16(let value):
                        writer.writeUInt8(6)
                        writer.writeUInt16(value)
                    case .uint32(let value):
                        writer.writeUInt8(7)
                        writer.writeUInt32(value)
                    case .uint64(let value):
                        writer.writeUInt8(8)
                        writer.writeUInt64(value)
                    case .string(let value):
                        writer.writeUInt8(9)
                        try writer.writeString(value)
                    case .bytes(let value):
                        writer.writeUInt8(10)
                        try writer.writeBytes(value)
                    case .uuid(let value):
                        writer.writeUInt8(11)
                        writer.writeUInt64(value.high)
                        writer.writeUInt64(value.low)
                    case .composite(let components):
                        guard !components.isEmpty else {
                            throw .invalidReferenceIdentifier(.emptyComposite)
                        }
                        writer.writeUInt8(12)
                        try writer.writeCount(components.count)
                        frames.append(
                            .identifierComposite(
                                components,
                                nextIndex: 0
                            )
                        )
                        continue
                    }
                    writer.endNestedValue()
                    openValueCount -= 1

                case .reference(let reference, let closesValue):
                    do {
                        try reference.id.validate()
                    } catch let error {
                        throw .invalidReferenceIdentifier(error)
                    }
                    try writer.writeString(reference.entity)
                    frames.append(
                        .referenceIdentifier(
                            reference,
                            closesValue: closesValue
                        )
                    )
                    nextNode = .identifier(reference.id)
                    continue
                }
                continue
            }

            switch frames.removeLast() {
            case .array(let values, let nextIndex):
                guard nextIndex < values.count else {
                    writer.endNestedValue()
                    openValueCount -= 1
                    continue
                }
                frames.append(.array(values, nextIndex: nextIndex + 1))
                nextNode = .value(values[nextIndex])

            case .object(let fields, let nextIndex):
                guard nextIndex < fields.count else {
                    writer.endNestedValue()
                    openValueCount -= 1
                    continue
                }
                frames.append(.object(fields, nextIndex: nextIndex + 1))
                nextNode = .objectField(fields[nextIndex])

            case .identifierComposite(let components, let nextIndex):
                guard nextIndex < components.count else {
                    writer.endNestedValue()
                    openValueCount -= 1
                    continue
                }
                frames.append(
                    .identifierComposite(
                        components,
                        nextIndex: nextIndex + 1
                    )
                )
                nextNode = .identifier(components[nextIndex])

            case .referenceIdentifier(let reference, let closesValue):
                let fields = reference.partitions.fields
                try writer.writeCount(fields.count)
                frames.append(
                    .referencePartitions(
                        reference,
                        fields: fields,
                        nextIndex: 0,
                        closesValue: closesValue
                    )
                )

            case .referencePartitions(
                let reference,
                let fields,
                let nextIndex,
                let closesValue
            ):
                guard nextIndex < fields.count else {
                    if closesValue {
                        writer.endNestedValue()
                        openValueCount -= 1
                    }
                    continue
                }
                frames.append(
                    .referencePartitions(
                        reference,
                        fields: fields,
                        nextIndex: nextIndex + 1,
                        closesValue: closesValue
                    )
                )
                nextNode = .objectField(fields[nextIndex])
            }
        }
    }

    enum DecodingRequest {
        case value
        case objectField
        case identifier
        case reference
    }

    enum DecodedNode {
        case value(FieldValue)
        case objectField(ObjectField)
        case identifier(ReferenceIdentifier)
        case reference(EntityReference)
    }

    enum DecodingFrame {
        case objectField(key: String)
        case array(values: [FieldValue], remaining: Int)
        case object(fields: [ObjectField], remaining: Int)
        case valueReference
        case identifierComposite(
            values: [ReferenceIdentifier],
            remaining: Int
        )
        case referenceIdentifier(entity: String)
        case referencePartitions(
            entity: String,
            id: ReferenceIdentifier,
            fields: [ObjectField],
            remaining: Int
        )
    }

    static func decode(
        _ root: DecodingRequest,
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> DecodedNode {
        var frames: [DecodingFrame] = []
        var nextRequest: DecodingRequest? = root
        var completed: DecodedNode?
        var openValueCount = 0

        defer {
            while openValueCount > 0 {
                reader.endNestedValue()
                openValueCount -= 1
            }
        }

        while true {
            if let request = nextRequest {
                nextRequest = nil
                switch request {
                case .value:
                    try reader.beginNestedValue()
                    openValueCount += 1

                    switch try reader.readUInt8() {
                    case 0:
                        completed = .value(.null)
                    case 1:
                        completed = .value(.bool(try reader.readBool()))
                    case 2:
                        completed = .value(.int8(try reader.readInt8()))
                    case 3:
                        completed = .value(.int16(try reader.readInt16()))
                    case 4:
                        completed = .value(.int32(try reader.readInt32()))
                    case 5:
                        completed = .value(.int64(try reader.readInt64()))
                    case 6:
                        completed = .value(.uint8(try reader.readUInt8()))
                    case 7:
                        completed = .value(.uint16(try reader.readUInt16()))
                    case 8:
                        completed = .value(.uint32(try reader.readUInt32()))
                    case 9:
                        completed = .value(.uint64(try reader.readUInt64()))
                    case 10:
                        completed = .value(.float32(try reader.readFloat()))
                    case 11:
                        completed = .value(.float64(try reader.readDouble()))
                    case 12:
                        completed = .value(
                            .decimal(
                                ExactDecimal(
                                    coefficient: try reader.readInt128(),
                                    scale: try reader.readInt32()
                                )
                            )
                        )
                    case 13:
                        completed = .value(.string(try reader.readString()))
                    case 14:
                        completed = .value(.bytes(try reader.readBytes()))
                    case 15:
                        completed = .value(.date(try decodeDate(from: &reader)))
                    case 16:
                        completed = .value(.time(try decodeTime(from: &reader)))
                    case 17:
                        completed = .value(
                            .dateTime(
                                CivilDateTime(
                                    date: try decodeDate(from: &reader),
                                    time: try decodeTime(from: &reader)
                                )
                            )
                        )
                    case 18:
                        completed = .value(
                            .timestamp(try decodeTimestamp(from: &reader))
                        )
                    case 19:
                        completed = .value(
                            .timeSpan(try decodeTimeSpan(from: &reader))
                        )
                    case 20:
                        completed = .value(
                            .calendarPeriod(
                                CalendarPeriod(
                                    months: try reader.readInt64(),
                                    days: try reader.readInt64()
                                )
                            )
                        )
                    case 21:
                        completed = .value(
                            .geographicPoint(
                                try decodeGeographicPoint(from: &reader)
                            )
                        )
                    case 22:
                        completed = .value(
                            .geographicPosition(
                                try decodeGeographicPosition(from: &reader)
                            )
                        )
                    case 23:
                        completed = .value(
                            .vector(try decodeVector(from: &reader))
                        )
                    case 24:
                        completed = .value(
                            .uuid(
                                UUID(
                                    high: try reader.readUInt64(),
                                    low: try reader.readUInt64()
                                )
                            )
                        )
                    case 25:
                        let count = try reader.readCount()
                        guard count > 0 else {
                            completed = .value(.array([]))
                            reader.endNestedValue()
                            openValueCount -= 1
                            continue
                        }
                        var values: [FieldValue] = []
                        values.reserveCapacity(count)
                        frames.append(.array(values: values, remaining: count))
                        nextRequest = .value
                        continue
                    case 26:
                        let count = try reader.readCount()
                        guard count > 0 else {
                            completed = .value(.object(FieldObject()))
                            reader.endNestedValue()
                            openValueCount -= 1
                            continue
                        }
                        var fields: [ObjectField] = []
                        fields.reserveCapacity(count)
                        frames.append(.object(fields: fields, remaining: count))
                        nextRequest = .objectField
                        continue
                    case 27:
                        frames.append(.valueReference)
                        nextRequest = .reference
                        continue
                    case 28:
                        completed = .value(
                            .rdfTerm(
                                try reader.readCanonicalRDFTerm(role: .term)
                            )
                        )
                    case let tag:
                        throw .invalidValueTag(tag)
                    }

                    reader.endNestedValue()
                    openValueCount -= 1

                case .objectField:
                    frames.append(
                        .objectField(key: try reader.readString())
                    )
                    nextRequest = .value
                    continue

                case .identifier:
                    try reader.beginNestedValue()
                    openValueCount += 1
                    switch try reader.readUInt8() {
                    case 0:
                        completed = .identifier(.bool(try reader.readBool()))
                    case 1:
                        completed = .identifier(.int8(try reader.readInt8()))
                    case 2:
                        completed = .identifier(.int16(try reader.readInt16()))
                    case 3:
                        completed = .identifier(.int32(try reader.readInt32()))
                    case 4:
                        completed = .identifier(.int64(try reader.readInt64()))
                    case 5:
                        completed = .identifier(.uint8(try reader.readUInt8()))
                    case 6:
                        completed = .identifier(.uint16(try reader.readUInt16()))
                    case 7:
                        completed = .identifier(.uint32(try reader.readUInt32()))
                    case 8:
                        completed = .identifier(.uint64(try reader.readUInt64()))
                    case 9:
                        completed = .identifier(.string(try reader.readString()))
                    case 10:
                        completed = .identifier(.bytes(try reader.readBytes()))
                    case 11:
                        completed = .identifier(
                            .uuid(
                                UUID(
                                    high: try reader.readUInt64(),
                                    low: try reader.readUInt64()
                                )
                            )
                        )
                    case 12:
                        let count = try reader.readCount()
                        guard count > 0 else {
                            throw .invalidReferenceIdentifier(.emptyComposite)
                        }
                        var values: [ReferenceIdentifier] = []
                        values.reserveCapacity(count)
                        frames.append(
                            .identifierComposite(
                                values: values,
                                remaining: count
                            )
                        )
                        nextRequest = .identifier
                        continue
                    case let tag:
                        throw .invalidReferenceIdentifierTag(tag)
                    }
                    reader.endNestedValue()
                    openValueCount -= 1

                case .reference:
                    frames.append(
                        .referenceIdentifier(entity: try reader.readString())
                    )
                    nextRequest = .identifier
                    continue
                }
                continue
            }

            guard let node = completed else {
                preconditionFailure("Field value decoder has no next operation")
            }
            completed = nil
            guard !frames.isEmpty else {
                return node
            }

            switch frames.removeLast() {
            case .objectField(let key):
                completed = .objectField(
                    (key: key, value: takeValue(consume node))
                )

            case .array(var values, let remaining):
                values.append(takeValue(consume node))
                if remaining == 1 {
                    reader.endNestedValue()
                    openValueCount -= 1
                    completed = .value(.array(consume values))
                } else {
                    frames.append(
                        .array(
                            values: consume values,
                            remaining: remaining - 1
                        )
                    )
                    nextRequest = .value
                }

            case .object(var fields, let remaining):
                fields.append(takeObjectField(consume node))
                if remaining == 1 {
                    let object = try canonicalObject(consume fields)
                    reader.endNestedValue()
                    openValueCount -= 1
                    completed = .value(.object(object))
                } else {
                    frames.append(
                        .object(
                            fields: consume fields,
                            remaining: remaining - 1
                        )
                    )
                    nextRequest = .objectField
                }

            case .valueReference:
                let reference = takeReference(consume node)
                reader.endNestedValue()
                openValueCount -= 1
                completed = .value(.reference(reference))

            case .identifierComposite(var values, let remaining):
                values.append(takeIdentifier(consume node))
                if remaining == 1 {
                    reader.endNestedValue()
                    openValueCount -= 1
                    completed = .identifier(.composite(consume values))
                } else {
                    frames.append(
                        .identifierComposite(
                            values: consume values,
                            remaining: remaining - 1
                        )
                    )
                    nextRequest = .identifier
                }

            case .referenceIdentifier(let entity):
                let identifier = takeIdentifier(consume node)
                do {
                    try identifier.validate()
                } catch let error {
                    throw .invalidReferenceIdentifier(error)
                }
                let partitionCount = try reader.readCount()
                guard partitionCount > 0 else {
                    completed = .reference(
                        try makeReference(
                            entity: entity,
                            id: consume identifier,
                            partitions: FieldObject()
                        )
                    )
                    continue
                }
                var fields: [ObjectField] = []
                fields.reserveCapacity(partitionCount)
                frames.append(
                    .referencePartitions(
                        entity: entity,
                        id: consume identifier,
                        fields: fields,
                        remaining: partitionCount
                    )
                )
                nextRequest = .objectField

            case .referencePartitions(
                let entity,
                let id,
                var fields,
                let remaining
            ):
                fields.append(takeObjectField(consume node))
                if remaining == 1 {
                    completed = .reference(
                        try makeReference(
                            entity: entity,
                            id: consume id,
                            partitions: canonicalObject(consume fields)
                        )
                    )
                } else {
                    frames.append(
                        .referencePartitions(
                            entity: entity,
                            id: consume id,
                            fields: consume fields,
                            remaining: remaining - 1
                        )
                    )
                    nextRequest = .objectField
                }
            }
        }
    }

    static func canonicalObject(
        _ fields: consuming [ObjectField]
    ) throws(DatabaseWireError) -> FieldObject {
        let originalKeys = fields.map(\.key)
        let object: FieldObject
        do {
            object = try FieldObject(consume fields)
        } catch let error {
            throw .invalidFieldObject(error)
        }
        let canonicalFields = object.fields
        guard originalKeys.count == canonicalFields.count else {
            throw .nonCanonicalFieldObject
        }
        for index in originalKeys.indices {
            guard originalKeys[index].utf8.elementsEqual(
                canonicalFields[index].key.utf8
            ) else {
                throw .nonCanonicalFieldObject
            }
        }
        return object
    }

    static func makeReference(
        entity: String,
        id: consuming ReferenceIdentifier,
        partitions: FieldObject
    ) throws(DatabaseWireError) -> EntityReference {
        do {
            return try EntityReference(
                entity: entity,
                id: consume id,
                partitions: partitions
            )
        } catch let error {
            throw .invalidEntityReference(error)
        }
    }

    static func decodeDate(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> CivilDate {
        let year = try reader.readInt32()
        let month = try reader.readUInt8()
        let day = try reader.readUInt8()
        do {
            return try CivilDate(
                year: year,
                month: month,
                day: day
            )
        } catch let error {
            throw .invalidCivilDate(error)
        }
    }

    static func decodeTime(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> CivilTime {
        let hour = try reader.readUInt8()
        let minute = try reader.readUInt8()
        let second = try reader.readUInt8()
        let nanoseconds = try reader.readUInt32()
        do {
            return try CivilTime(
                hour: hour,
                minute: minute,
                second: second,
                nanoseconds: nanoseconds
            )
        } catch let error {
            throw .invalidCivilTime(error)
        }
    }

    static func decodeTimestamp(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> Timestamp {
        let seconds = try reader.readInt64()
        let nanoseconds = try reader.readUInt32()
        do {
            return try Timestamp(
                secondsSinceUnixEpoch: seconds,
                nanoseconds: nanoseconds
            )
        } catch {
            throw .invalidTimestamp
        }
    }

    static func decodeTimeSpan(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> TimeSpan {
        let seconds = try reader.readInt64()
        let nanoseconds = try reader.readUInt32()
        do {
            return try TimeSpan(
                seconds: seconds,
                nanoseconds: nanoseconds
            )
        } catch let error {
            throw .invalidTimeSpan(error)
        }
    }

    static func decodeGeographicPoint(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> GeographicPoint {
        let latitude = try reader.readDouble()
        let longitude = try reader.readDouble()
        do {
            return try GeographicPoint(
                latitude: latitude,
                longitude: longitude
            )
        } catch let error {
            throw .invalidGeographicPoint(error)
        }
    }

    static func decodeGeographicPosition(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> GeographicPosition {
        let latitude = try reader.readDouble()
        let longitude = try reader.readDouble()
        let height = try reader.readDouble()
        do {
            return try GeographicPosition(
                latitude: latitude,
                longitude: longitude,
                ellipsoidalHeightInMeters: height
            )
        } catch let error {
            throw .invalidGeographicPosition(error)
        }
    }

    static func encodeVector(
        _ vector: Vector,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch vector.elementType {
        case .int8:
            writer.writeUInt8(0)
            try writer.writeCount(vector.count)
            _ = vector.withInt8Elements {
                for value in $0 { writer.writeInt8(value) }
            }
        case .int16:
            writer.writeUInt8(1)
            try writer.writeCount(vector.count)
            _ = vector.withInt16Elements {
                for value in $0 { writer.writeInt16(value) }
            }
        case .int32:
            writer.writeUInt8(2)
            try writer.writeCount(vector.count)
            _ = vector.withInt32Elements {
                for value in $0 { writer.writeInt32(value) }
            }
        case .int64:
            writer.writeUInt8(3)
            try writer.writeCount(vector.count)
            _ = vector.withInt64Elements {
                for value in $0 { writer.writeInt64(value) }
            }
        case .uint8:
            writer.writeUInt8(4)
            try writer.writeCount(vector.count)
            _ = vector.withUInt8Elements {
                for value in $0 { writer.writeUInt8(value) }
            }
        case .uint16:
            writer.writeUInt8(5)
            try writer.writeCount(vector.count)
            _ = vector.withUInt16Elements {
                for value in $0 { writer.writeUInt16(value) }
            }
        case .uint32:
            writer.writeUInt8(6)
            try writer.writeCount(vector.count)
            _ = vector.withUInt32Elements {
                for value in $0 { writer.writeUInt32(value) }
            }
        case .uint64:
            writer.writeUInt8(7)
            try writer.writeCount(vector.count)
            _ = vector.withUInt64Elements {
                for value in $0 { writer.writeUInt64(value) }
            }
        case .float32:
            writer.writeUInt8(8)
            try writer.writeCount(vector.count)
            _ = vector.withFloat32Elements {
                for value in $0 { writer.writeFloat(value) }
            }
        case .float64:
            writer.writeUInt8(9)
            try writer.writeCount(vector.count)
            _ = vector.withFloat64Elements {
                for value in $0 { writer.writeDouble(value) }
            }
        }
    }

    static func decodeVector(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> Vector {
        let elementType = try reader.readUInt8()
        let count = try reader.readCount()
        switch elementType {
        case 0:
            var values: [Int8] = []
            values.reserveCapacity(count)
            for _ in 0..<count { values.append(try reader.readInt8()) }
            return Vector(int8: values)
        case 1:
            var values: [Int16] = []
            values.reserveCapacity(count)
            for _ in 0..<count { values.append(try reader.readInt16()) }
            return Vector(int16: values)
        case 2:
            var values: [Int32] = []
            values.reserveCapacity(count)
            for _ in 0..<count { values.append(try reader.readInt32()) }
            return Vector(int32: values)
        case 3:
            var values: [Int64] = []
            values.reserveCapacity(count)
            for _ in 0..<count { values.append(try reader.readInt64()) }
            return Vector(int64: values)
        case 4:
            var values: [UInt8] = []
            values.reserveCapacity(count)
            for _ in 0..<count { values.append(try reader.readUInt8()) }
            return Vector(uint8: values)
        case 5:
            var values: [UInt16] = []
            values.reserveCapacity(count)
            for _ in 0..<count { values.append(try reader.readUInt16()) }
            return Vector(uint16: values)
        case 6:
            var values: [UInt32] = []
            values.reserveCapacity(count)
            for _ in 0..<count { values.append(try reader.readUInt32()) }
            return Vector(uint32: values)
        case 7:
            var values: [UInt64] = []
            values.reserveCapacity(count)
            for _ in 0..<count { values.append(try reader.readUInt64()) }
            return Vector(uint64: values)
        case 8:
            var values: [Float] = []
            values.reserveCapacity(count)
            for _ in 0..<count { values.append(try reader.readFloat()) }
            do {
                return try Vector(float32: values)
            } catch let error {
                throw .invalidVector(error)
            }
        case 9:
            var values: [Double] = []
            values.reserveCapacity(count)
            for _ in 0..<count { values.append(try reader.readDouble()) }
            do {
                return try Vector(float64: values)
            } catch let error {
                throw .invalidVector(error)
            }
        case let tag:
            throw .invalidValueTag(tag)
        }
    }

    static func takeValue(
        _ node: consuming DecodedNode
    ) -> FieldValue {
        switch consume node {
        case .value(let value):
            return value
        case .objectField, .identifier, .reference:
            preconditionFailure("Field value decoder expected a value")
        }
    }

    static func takeObjectField(
        _ node: consuming DecodedNode
    ) -> ObjectField {
        switch consume node {
        case .objectField(let field):
            return field
        case .value, .identifier, .reference:
            preconditionFailure("Field value decoder expected an object field")
        }
    }

    static func takeIdentifier(
        _ node: consuming DecodedNode
    ) -> ReferenceIdentifier {
        switch consume node {
        case .identifier(let identifier):
            return identifier
        case .value, .objectField, .reference:
            preconditionFailure("Field value decoder expected an identifier")
        }
    }

    static func takeReference(
        _ node: consuming DecodedNode
    ) -> EntityReference {
        switch consume node {
        case .reference(let reference):
            return reference
        case .value, .objectField, .identifier:
            preconditionFailure("Field value decoder expected a reference")
        }
    }
}
