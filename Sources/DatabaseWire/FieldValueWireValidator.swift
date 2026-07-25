import DatabaseKit
import DatabaseTypes

/// Validates recursive field values without materializing their semantic tree.
///
/// The validator advances the original bounded reader, retains only one frame
/// per nesting level, and borrows object keys from the input owner solely for
/// canonical-order comparison.
enum FieldValueWireValidator {
    static func validateValue(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        try validate(.value, from: &reader)
    }

    static func validateObject(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        try validate(.object, from: &reader)
    }
}

private extension FieldValueWireValidator {
    enum Request {
        case value
        case object
        case objectField
        case identifier
        case reference
    }

    enum Completion {
        case value
        case object
        case objectField(ByteString)
        case identifier
        case reference
    }

    enum Frame {
        case objectField(ByteString)
        case array(remaining: Int)
        case valueObject(remaining: Int, previousKey: ByteString?)
        case standaloneObject(remaining: Int, previousKey: ByteString?)
        case valueReference
        case identifierComposite(remaining: Int)
        case referenceIdentifier
        case referencePartitions(
            remaining: Int,
            previousKey: ByteString?
        )
    }

    static func validate(
        _ root: Request,
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        var frames: [Frame] = []
        var nextRequest: Request? = root
        var completion: Completion?
        var openValueCount = 0

        defer { reader.abandonNestedValues(openValueCount) }

        while true {
            if let request = nextRequest {
                nextRequest = nil
                switch request {
                case .value:
                    try reader.beginNestedValue()
                    openValueCount += 1
                    let tag = try reader.readUInt8()
                    switch tag {
                    case 0:
                        completion = .value
                    case 1:
                        _ = try reader.readBool()
                        completion = .value
                    case 2:
                        _ = try reader.readInt8()
                        completion = .value
                    case 3:
                        _ = try reader.readInt16()
                        completion = .value
                    case 4:
                        _ = try reader.readInt32()
                        completion = .value
                    case 5:
                        _ = try reader.readInt64()
                        completion = .value
                    case 6:
                        _ = try reader.readUInt8()
                        completion = .value
                    case 7:
                        _ = try reader.readUInt16()
                        completion = .value
                    case 8:
                        _ = try reader.readUInt32()
                        completion = .value
                    case 9:
                        _ = try reader.readUInt64()
                        completion = .value
                    case 10:
                        _ = try reader.readFloat()
                        completion = .value
                    case 11:
                        _ = try reader.readDouble()
                        completion = .value
                    case 12:
                        _ = try reader.readInt128()
                        _ = try reader.readInt32()
                        completion = .value
                    case 13:
                        _ = try reader.readValidatedUTF8Bytes()
                        completion = .value
                    case 14:
                        _ = try reader.readBytes()
                        completion = .value
                    case 15:
                        try validateDate(from: &reader)
                        completion = .value
                    case 16:
                        try validateTime(from: &reader)
                        completion = .value
                    case 17:
                        try validateDate(from: &reader)
                        try validateTime(from: &reader)
                        completion = .value
                    case 18:
                        try validateTimestamp(from: &reader)
                        completion = .value
                    case 19:
                        try validateTimeSpan(from: &reader)
                        completion = .value
                    case 20:
                        _ = try reader.readInt64()
                        _ = try reader.readInt64()
                        completion = .value
                    case 21:
                        try validateGeographicPoint(from: &reader)
                        completion = .value
                    case 22:
                        try validateGeographicPosition(from: &reader)
                        completion = .value
                    case 23:
                        try validateVector(from: &reader)
                        completion = .value
                    case 24:
                        _ = try reader.readUInt64()
                        _ = try reader.readUInt64()
                        completion = .value
                    case 25:
                        let count = try reader.readCount()
                        guard count > 0 else {
                            try reader.endNestedValue()
                            openValueCount -= 1
                            completion = .value
                            continue
                        }
                        frames.append(.array(remaining: count))
                        nextRequest = .value
                        continue
                    case 26:
                        let count = try reader.readCount()
                        guard count > 0 else {
                            try reader.endNestedValue()
                            openValueCount -= 1
                            completion = .value
                            continue
                        }
                        frames.append(
                            .valueObject(
                                remaining: count,
                                previousKey: nil
                            )
                        )
                        nextRequest = .objectField
                        continue
                    case 27:
                        frames.append(.valueReference)
                        nextRequest = .reference
                        continue
                    case 28:
                        try reader.validateCanonicalRDFTerm(role: .term)
                        completion = .value
                    case let invalidTag:
                        throw .invalidValueTag(invalidTag)
                    }

                    try reader.endNestedValue()
                    openValueCount -= 1

                case .object:
                    let count = try reader.readCount()
                    guard count > 0 else {
                        completion = .object
                        continue
                    }
                    frames.append(
                        .standaloneObject(
                            remaining: count,
                            previousKey: nil
                        )
                    )
                    nextRequest = .objectField
                    continue

                case .objectField:
                    let key = try reader.readValidatedUTF8Bytes()
                    frames.append(.objectField(key))
                    nextRequest = .value
                    continue

                case .identifier:
                    try reader.beginNestedValue()
                    openValueCount += 1
                    switch try reader.readUInt8() {
                    case 0:
                        _ = try reader.readBool()
                        completion = .identifier
                    case 1:
                        _ = try reader.readInt8()
                        completion = .identifier
                    case 2:
                        _ = try reader.readInt16()
                        completion = .identifier
                    case 3:
                        _ = try reader.readInt32()
                        completion = .identifier
                    case 4:
                        _ = try reader.readInt64()
                        completion = .identifier
                    case 5:
                        _ = try reader.readUInt8()
                        completion = .identifier
                    case 6:
                        _ = try reader.readUInt16()
                        completion = .identifier
                    case 7:
                        _ = try reader.readUInt32()
                        completion = .identifier
                    case 8:
                        _ = try reader.readUInt64()
                        completion = .identifier
                    case 9:
                        _ = try reader.readValidatedUTF8Bytes()
                        completion = .identifier
                    case 10:
                        _ = try reader.readBytes()
                        completion = .identifier
                    case 11:
                        _ = try reader.readUInt64()
                        _ = try reader.readUInt64()
                        completion = .identifier
                    case 12:
                        let count = try reader.readCount()
                        guard count > 0 else {
                            throw .invalidReferenceIdentifier(.emptyComposite)
                        }
                        frames.append(
                            .identifierComposite(remaining: count)
                        )
                        nextRequest = .identifier
                        continue
                    case let invalidTag:
                        throw .invalidReferenceIdentifierTag(invalidTag)
                    }
                    try reader.endNestedValue()
                    openValueCount -= 1

                case .reference:
                    let entity = try reader.readValidatedUTF8Bytes()
                    guard !entity.isEmpty else {
                        throw .invalidEntityReference(.emptyEntity)
                    }
                    frames.append(.referenceIdentifier)
                    nextRequest = .identifier
                    continue
                }
                continue
            }

            guard let completed = completion else {
                throw .invalidFieldValueWireState
            }
            completion = nil
            guard let frame = frames.popLast() else {
                switch (root, completed) {
                case (.value, .value), (.object, .object):
                    return
                default:
                    throw .invalidFieldValueWireState
                }
            }

            switch frame {
            case .objectField(let key):
                guard case .value = completed else {
                    throw .invalidFieldValueWireState
                }
                completion = .objectField(key)

            case .array(let remaining):
                guard case .value = completed else {
                    throw .invalidFieldValueWireState
                }
                if remaining == 1 {
                    try reader.endNestedValue()
                    openValueCount -= 1
                    completion = .value
                } else {
                    frames.append(.array(remaining: remaining - 1))
                    nextRequest = .value
                }

            case .valueObject(let remaining, let previousKey):
                let key = try takeObjectKey(completed)
                try validateCanonicalKey(previousKey, before: key)
                if remaining == 1 {
                    try reader.endNestedValue()
                    openValueCount -= 1
                    completion = .value
                } else {
                    frames.append(
                        .valueObject(
                            remaining: remaining - 1,
                            previousKey: key
                        )
                    )
                    nextRequest = .objectField
                }

            case .standaloneObject(let remaining, let previousKey):
                let key = try takeObjectKey(completed)
                try validateCanonicalKey(previousKey, before: key)
                if remaining == 1 {
                    completion = .object
                } else {
                    frames.append(
                        .standaloneObject(
                            remaining: remaining - 1,
                            previousKey: key
                        )
                    )
                    nextRequest = .objectField
                }

            case .valueReference:
                guard case .reference = completed else {
                    throw .invalidFieldValueWireState
                }
                try reader.endNestedValue()
                openValueCount -= 1
                completion = .value

            case .identifierComposite(let remaining):
                guard case .identifier = completed else {
                    throw .invalidFieldValueWireState
                }
                if remaining == 1 {
                    try reader.endNestedValue()
                    openValueCount -= 1
                    completion = .identifier
                } else {
                    frames.append(
                        .identifierComposite(remaining: remaining - 1)
                    )
                    nextRequest = .identifier
                }

            case .referenceIdentifier:
                guard case .identifier = completed else {
                    throw .invalidFieldValueWireState
                }
                let count = try reader.readCount()
                guard count > 0 else {
                    completion = .reference
                    continue
                }
                frames.append(
                    .referencePartitions(
                        remaining: count,
                        previousKey: nil
                    )
                )
                nextRequest = .objectField

            case .referencePartitions(let remaining, let previousKey):
                let key = try takeObjectKey(completed)
                try validateCanonicalKey(previousKey, before: key)
                if remaining == 1 {
                    completion = .reference
                } else {
                    frames.append(
                        .referencePartitions(
                            remaining: remaining - 1,
                            previousKey: key
                        )
                    )
                    nextRequest = .objectField
                }
            }
        }
    }

    static func takeObjectKey(
        _ completion: consuming Completion
    ) throws(DatabaseWireError) -> ByteString {
        guard case .objectField(let key) = completion else {
            throw .invalidFieldValueWireState
        }
        return key
    }

    static func validateCanonicalKey(
        _ previous: ByteString?,
        before key: ByteString
    ) throws(DatabaseWireError) {
        guard let previous else {
            return
        }
        guard compare(previous, key) < 0 else {
            throw .nonCanonicalFieldObject
        }
    }

    static func compare(_ left: ByteString, _ right: ByteString) -> Int {
        left.withUnsafeBytes { leftBytes in
            right.withUnsafeBytes { rightBytes in
                let sharedCount = min(leftBytes.count, rightBytes.count)
                for index in 0..<sharedCount {
                    if leftBytes[index] < rightBytes[index] {
                        return -1
                    }
                    if leftBytes[index] > rightBytes[index] {
                        return 1
                    }
                }
                if leftBytes.count < rightBytes.count {
                    return -1
                }
                if leftBytes.count > rightBytes.count {
                    return 1
                }
                return 0
            }
        }
    }

    static func validateDate(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let year = try reader.readInt32()
        let month = try reader.readUInt8()
        let day = try reader.readUInt8()
        do {
            _ = try CivilDate(
                year: year,
                month: month,
                day: day
            )
        } catch let error {
            throw .invalidCivilDate(error)
        }
    }

    static func validateTime(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let hour = try reader.readUInt8()
        let minute = try reader.readUInt8()
        let second = try reader.readUInt8()
        let nanoseconds = try reader.readUInt32()
        do {
            _ = try CivilTime(
                hour: hour,
                minute: minute,
                second: second,
                nanoseconds: nanoseconds
            )
        } catch let error {
            throw .invalidCivilTime(error)
        }
    }

    static func validateTimestamp(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let seconds = try reader.readInt64()
        let nanoseconds = try reader.readUInt32()
        do {
            _ = try Timestamp(
                secondsSinceUnixEpoch: seconds,
                nanoseconds: nanoseconds
            )
        } catch {
            throw .invalidTimestamp
        }
    }

    static func validateTimeSpan(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let seconds = try reader.readInt64()
        let nanoseconds = try reader.readUInt32()
        do {
            _ = try TimeSpan(
                seconds: seconds,
                nanoseconds: nanoseconds
            )
        } catch let error {
            throw .invalidTimeSpan(error)
        }
    }

    static func validateGeographicPoint(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let latitude = try reader.readDouble()
        let longitude = try reader.readDouble()
        do {
            _ = try GeographicPoint(
                latitude: latitude,
                longitude: longitude
            )
        } catch let error {
            throw .invalidGeographicPoint(error)
        }
    }

    static func validateGeographicPosition(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let latitude = try reader.readDouble()
        let longitude = try reader.readDouble()
        let height = try reader.readDouble()
        do {
            _ = try GeographicPosition(
                latitude: latitude,
                longitude: longitude,
                ellipsoidalHeightInMeters: height
            )
        } catch let error {
            throw .invalidGeographicPosition(error)
        }
    }

    static func validateVector(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let elementType = try reader.readUInt8()
        let count = try reader.readCount()
        for index in 0..<count {
            switch elementType {
            case 0:
                _ = try reader.readInt8()
            case 1:
                _ = try reader.readInt16()
            case 2:
                _ = try reader.readInt32()
            case 3:
                _ = try reader.readInt64()
            case 4:
                _ = try reader.readUInt8()
            case 5:
                _ = try reader.readUInt16()
            case 6:
                _ = try reader.readUInt32()
            case 7:
                _ = try reader.readUInt64()
            case 8:
                let value = try reader.readFloat()
                guard value.isFinite else {
                    throw .invalidVector(.nonFiniteFloat32(index: index))
                }
            case 9:
                let value = try reader.readDouble()
                guard value.isFinite else {
                    throw .invalidVector(.nonFiniteFloat64(index: index))
                }
            case let invalidTag:
                throw .invalidValueTag(invalidTag)
            }
        }
    }
}
