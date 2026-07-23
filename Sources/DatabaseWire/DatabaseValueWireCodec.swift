import DatabaseValue

/// Encodes and decodes the recursive DatabaseValue wire component without
/// growing the process stack recursively.
///
/// Each open container owns one cursor frame. Collection elements are visited
/// one at a time, so traversal metadata is proportional to nesting depth rather
/// than the total number of values.
enum DatabaseValueWireCodec {
    static func encode(
        _ value: DatabaseValue,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encode(.value(value), into: &writer)
    }

    static func encode(
        _ field: DatabaseObjectField,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encode(.field(field), into: &writer)
    }

    static func encode(
        _ identity: PersistableIdentity,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encode(
            .identity(identity, closesValue: false),
            into: &writer
        )
    }

    static func decodeValue(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> DatabaseValue {
        switch try decode(.value, from: &reader) {
        case .value(let value):
            return value
        case .field, .identifier, .identity:
            preconditionFailure("Database value decoder produced the wrong root type")
        }
    }

    static func decodeField(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> DatabaseObjectField {
        switch try decode(.field, from: &reader) {
        case .field(let field):
            return field
        case .value, .identifier, .identity:
            preconditionFailure("Database value decoder produced the wrong root type")
        }
    }

    static func decodeIdentity(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> PersistableIdentity {
        switch try decode(.identity, from: &reader) {
        case .identity(let identity):
            return identity
        case .value, .field, .identifier:
            preconditionFailure("Database value decoder produced the wrong root type")
        }
    }
}

private extension DatabaseValueWireCodec {
    enum EncodingNode {
        case value(DatabaseValue)
        case field(DatabaseObjectField)
        case identifier(PersistableIdentifierValue)
        case identity(PersistableIdentity, closesValue: Bool)
    }

    enum EncodingFrame {
        case array([DatabaseValue], nextIndex: Int)
        case object([DatabaseObjectField], nextIndex: Int)
        case identifierComposite([PersistableIdentifierValue], nextIndex: Int)
        case identityIdentifier(PersistableIdentity, closesValue: Bool)
        case identityPartitions(
            PersistableIdentity,
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
                    case .int64(let value):
                        writer.writeUInt8(2)
                        writer.writeInt64(value)
                    case .uint64(let value):
                        writer.writeUInt8(3)
                        writer.writeUInt64(value)
                    case .double(let value):
                        writer.writeUInt8(4)
                        writer.writeDouble(value)
                    case .decimal(let coefficient, let scale):
                        writer.writeUInt8(5)
                        writer.writeInt64(coefficient)
                        writer.writeInt32(scale)
                    case .string(let value):
                        writer.writeUInt8(6)
                        try writer.writeString(value)
                    case .bytes(let value):
                        writer.writeUInt8(7)
                        try writer.writeBytes(value)
                    case .date(let value):
                        writer.writeUInt8(8)
                        writer.writeInt32(value.year)
                        writer.writeUInt8(value.month)
                        writer.writeUInt8(value.day)
                    case .timestamp(let value):
                        writer.writeUInt8(9)
                        writer.writeInt64(value.secondsSinceUnixEpoch)
                        writer.writeUInt32(value.nanoseconds)
                    case .array(let values):
                        writer.writeUInt8(10)
                        try writer.writeCount(values.count)
                        frames.append(.array(values, nextIndex: 0))
                        continue
                    case .object(let fields):
                        writer.writeUInt8(11)
                        try writer.writeCount(fields.count)
                        frames.append(.object(fields, nextIndex: 0))
                        continue
                    case .reference(let identity):
                        writer.writeUInt8(12)
                        nextNode = .identity(identity, closesValue: true)
                        continue
                    case .rdfTerm(let term):
                        writer.writeUInt8(13)
                        try writer.writeCanonicalRDFTerm(term)
                    case .uuid(let value):
                        writer.writeUInt8(14)
                        writer.writeUInt64(value.high)
                        writer.writeUInt64(value.low)
                    }

                    writer.endNestedValue()
                    openValueCount -= 1

                case .field(let field):
                    writer.writeUInt32(field.number)
                    try writer.writeString(field.name)
                    nextNode = .value(field.value)

                case .identifier(let identifier):
                    try writer.beginNestedValue()
                    openValueCount += 1

                    switch identifier {
                    case .bool(let value):
                        writer.writeUInt8(0)
                        writer.writeBool(value)
                    case .int64(let value):
                        writer.writeUInt8(1)
                        writer.writeInt64(value)
                    case .uint64(let value):
                        writer.writeUInt8(2)
                        writer.writeUInt64(value)
                    case .string(let value):
                        writer.writeUInt8(3)
                        try writer.writeString(value)
                    case .bytes(let value):
                        writer.writeUInt8(4)
                        try writer.writeBytes(value)
                    case .uuid(let value):
                        writer.writeUInt8(5)
                        writer.writeUInt64(value.high)
                        writer.writeUInt64(value.low)
                    case .composite(let components):
                        guard !components.isEmpty else {
                            throw .emptyPersistableIdentifierComposite
                        }
                        writer.writeUInt8(6)
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

                case .identity(let identity, let closesValue):
                    do {
                        try PersistableIdentifierValidator.validateStructure(
                            identity.id
                        )
                    } catch let error {
                        throw .invalidPersistableIdentifier(error)
                    }
                    try writer.writeString(identity.entity)
                    frames.append(
                        .identityIdentifier(
                            identity,
                            closesValue: closesValue
                        )
                    )
                    nextNode = .identifier(identity.id)
                    continue
                }
                continue
            }

            switch frames.removeLast() {
            case .array(let values, let nextIndex):
                guard nextIndex < values.count else {
                    precondition(openValueCount > 0)
                    writer.endNestedValue()
                    openValueCount -= 1
                    continue
                }
                frames.append(
                    .array(values, nextIndex: nextIndex + 1)
                )
                nextNode = .value(values[nextIndex])

            case .object(let fields, let nextIndex):
                guard nextIndex < fields.count else {
                    precondition(openValueCount > 0)
                    writer.endNestedValue()
                    openValueCount -= 1
                    continue
                }
                frames.append(
                    .object(fields, nextIndex: nextIndex + 1)
                )
                nextNode = .field(fields[nextIndex])

            case .identifierComposite(let components, let nextIndex):
                guard nextIndex < components.count else {
                    precondition(openValueCount > 0)
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

            case .identityIdentifier(let identity, let closesValue):
                try writer.writeCount(identity.partitions.count)
                frames.append(
                    .identityPartitions(
                        identity,
                        nextIndex: 0,
                        closesValue: closesValue
                    )
                )

            case .identityPartitions(
                let identity,
                let nextIndex,
                let closesValue
            ):
                guard nextIndex < identity.partitions.count else {
                    if closesValue {
                        precondition(openValueCount > 0)
                        writer.endNestedValue()
                        openValueCount -= 1
                    }
                    continue
                }
                frames.append(
                    .identityPartitions(
                        identity,
                        nextIndex: nextIndex + 1,
                        closesValue: closesValue
                    )
                )
                nextNode = .field(identity.partitions[nextIndex])
            }
        }
    }

    enum DecodingRequest {
        case value
        case field
        case identifier
        case identity
    }

    enum DecodedNode {
        case value(DatabaseValue)
        case field(DatabaseObjectField)
        case identifier(PersistableIdentifierValue)
        case identity(PersistableIdentity)
    }

    enum DecodingFrame {
        case field(number: UInt32, name: String)
        case array(values: [DatabaseValue], remaining: Int)
        case object(fields: [DatabaseObjectField], remaining: Int)
        case reference
        case identifierComposite(
            values: [PersistableIdentifierValue],
            remaining: Int
        )
        case identityIdentifier(entity: String)
        case identityPartitions(
            entity: String,
            id: PersistableIdentifierValue,
            fields: [DatabaseObjectField],
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
                        completed = .value(.int64(try reader.readInt64()))
                    case 3:
                        completed = .value(.uint64(try reader.readUInt64()))
                    case 4:
                        completed = .value(.double(try reader.readDouble()))
                    case 5:
                        completed = .value(
                            .decimal(
                                coefficient: try reader.readInt64(),
                                scale: try reader.readInt32()
                            )
                        )
                    case 6:
                        completed = .value(.string(try reader.readString()))
                    case 7:
                        completed = .value(.bytes(try reader.readBytes()))
                    case 8:
                        completed = .value(
                            .date(
                                DatabaseDate(
                                    year: try reader.readInt32(),
                                    month: try reader.readUInt8(),
                                    day: try reader.readUInt8()
                                )
                            )
                        )
                    case 9:
                        completed = .value(
                            .timestamp(
                                DatabaseTimestamp(
                                    secondsSinceUnixEpoch: try reader.readInt64(),
                                    nanoseconds: try reader.readUInt32()
                                )
                            )
                        )
                    case 10:
                        let count = try reader.readCount()
                        guard count > 0 else {
                            completed = .value(.array([]))
                            reader.endNestedValue()
                            openValueCount -= 1
                            continue
                        }
                        var values: [DatabaseValue] = []
                        values.reserveCapacity(count)
                        frames.append(
                            .array(values: values, remaining: count)
                        )
                        nextRequest = .value
                        continue
                    case 11:
                        let count = try reader.readCount()
                        guard count > 0 else {
                            completed = .value(.object([]))
                            reader.endNestedValue()
                            openValueCount -= 1
                            continue
                        }
                        var fields: [DatabaseObjectField] = []
                        fields.reserveCapacity(count)
                        frames.append(
                            .object(fields: fields, remaining: count)
                        )
                        nextRequest = .field
                        continue
                    case 12:
                        frames.append(.reference)
                        nextRequest = .identity
                        continue
                    case 13:
                        completed = .value(
                            .rdfTerm(
                                try reader.readCanonicalRDFTerm(role: .term)
                            )
                        )
                    case 14:
                        completed = .value(
                            .uuid(
                                DatabaseUUID(
                                    high: try reader.readUInt64(),
                                    low: try reader.readUInt64()
                                )
                            )
                        )
                    case let tag:
                        throw .invalidValueTag(tag)
                    }

                    reader.endNestedValue()
                    openValueCount -= 1

                case .field:
                    let number = try reader.readUInt32()
                    let name = try reader.readString()
                    frames.append(.field(number: number, name: name))
                    nextRequest = .value
                    continue

                case .identifier:
                    try reader.beginNestedValue()
                    openValueCount += 1

                    switch try reader.readUInt8() {
                    case 0:
                        completed = .identifier(.bool(try reader.readBool()))
                    case 1:
                        completed = .identifier(.int64(try reader.readInt64()))
                    case 2:
                        completed = .identifier(.uint64(try reader.readUInt64()))
                    case 3:
                        completed = .identifier(.string(try reader.readString()))
                    case 4:
                        completed = .identifier(.bytes(try reader.readBytes()))
                    case 5:
                        completed = .identifier(
                            .uuid(
                                DatabaseUUID(
                                    high: try reader.readUInt64(),
                                    low: try reader.readUInt64()
                                )
                            )
                        )
                    case 6:
                        let count = try reader.readCount()
                        guard count > 0 else {
                            throw .emptyPersistableIdentifierComposite
                        }
                        guard count <= PersistableIdentifierLimits.default.maximumComponentCount else {
                            throw .invalidPersistableIdentifier(
                                .componentCountExceeded(
                                    actual: count,
                                    maximum: PersistableIdentifierLimits.default.maximumComponentCount
                                )
                            )
                        }
                        var values: [PersistableIdentifierValue] = []
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
                        throw .invalidPersistableIdentifierTag(tag)
                    }

                    reader.endNestedValue()
                    openValueCount -= 1

                case .identity:
                    let entity = try reader.readString()
                    frames.append(.identityIdentifier(entity: entity))
                    nextRequest = .identifier
                    continue
                }
                continue
            }

            guard let node = completed else {
                preconditionFailure("Database value decoder has no next operation")
            }
            completed = nil

            guard !frames.isEmpty else {
                return node
            }

            let frame = frames.removeLast()
            switch consume frame {
            case .field(let number, let name):
                let value = takeValue(consume node)
                completed = .field(
                    DatabaseObjectField(
                        number: number,
                        name: name,
                        value: value
                    )
                )

            case .array(var values, let remaining):
                let value = takeValue(consume node)
                values.append(consume value)
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
                let field = takeField(consume node)
                fields.append(consume field)
                if remaining == 1 {
                    reader.endNestedValue()
                    openValueCount -= 1
                    completed = .value(.object(consume fields))
                } else {
                    frames.append(
                        .object(
                            fields: consume fields,
                            remaining: remaining - 1
                        )
                    )
                    nextRequest = .field
                }

            case .reference:
                let identity = takeIdentity(consume node)
                reader.endNestedValue()
                openValueCount -= 1
                completed = .value(.reference(identity))

            case .identifierComposite(
                var values,
                let remaining
            ):
                let value = takeIdentifier(consume node)
                values.append(consume value)
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

            case .identityIdentifier(let entity):
                let identifier = takeIdentifier(consume node)
                do {
                    try PersistableIdentifierValidator.validateStructure(identifier)
                } catch let error {
                    throw .invalidPersistableIdentifier(error)
                }
                let partitionCount = try reader.readCount()
                guard partitionCount > 0 else {
                    completed = .identity(
                        PersistableIdentity(
                            entity: entity,
                            id: consume identifier
                        )
                    )
                    continue
                }
                var fields: [DatabaseObjectField] = []
                fields.reserveCapacity(partitionCount)
                frames.append(
                    .identityPartitions(
                        entity: entity,
                        id: consume identifier,
                        fields: fields,
                        remaining: partitionCount
                    )
                )
                nextRequest = .field

            case .identityPartitions(
                let entity,
                let id,
                var fields,
                let remaining
            ):
                let field = takeField(consume node)
                fields.append(consume field)
                if remaining == 1 {
                    completed = .identity(
                        PersistableIdentity(
                            entity: entity,
                            id: consume id,
                            partitions: consume fields
                        )
                    )
                } else {
                    frames.append(
                        .identityPartitions(
                            entity: entity,
                            id: consume id,
                            fields: consume fields,
                            remaining: remaining - 1
                        )
                    )
                    nextRequest = .field
                }
            }
        }
    }

    static func takeValue(
        _ node: consuming DecodedNode
    ) -> DatabaseValue {
        switch consume node {
        case .value(let value):
            return value
        case .field, .identifier, .identity:
            preconditionFailure("Database value decoder expected a value")
        }
    }

    static func takeField(
        _ node: consuming DecodedNode
    ) -> DatabaseObjectField {
        switch consume node {
        case .field(let field):
            return field
        case .value, .identifier, .identity:
            preconditionFailure("Database value decoder expected a field")
        }
    }

    static func takeIdentifier(
        _ node: consuming DecodedNode
    ) -> PersistableIdentifierValue {
        switch consume node {
        case .identifier(let identifier):
            return identifier
        case .value, .field, .identity:
            preconditionFailure("Database value decoder expected a persistable identifier")
        }
    }

    static func takeIdentity(
        _ node: consuming DecodedNode
    ) -> PersistableIdentity {
        switch consume node {
        case .identity(let identity):
            return identity
        case .value, .field, .identifier:
            preconditionFailure("Database value decoder expected an identity")
        }
    }
}
