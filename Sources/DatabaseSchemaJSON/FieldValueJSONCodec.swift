import DatabaseTypes

struct FieldValueJSONCodec: Sendable {
    let maximumBytes: Int
    let maximumDepth: Int
    let maximumCollectionCount: Int

    func encode(_ value: FieldValue) throws -> JSONValue {
        try encode(value, depth: 0)
    }

    func decode(_ value: JSONValue, path: String) throws -> FieldValue {
        try decode(value, path: path, depth: 0)
    }
}

private extension FieldValueJSONCodec {
    func encode(_ value: FieldValue, depth: Int) throws -> JSONValue {
        try requireDepth(depth)
        switch value {
        case .null: return tagged("null")
        case .bool(let value): return tagged("bool", "value", .bool(value))
        case .int8(let value): return integer("int8", value)
        case .int16(let value): return integer("int16", value)
        case .int32(let value): return integer("int32", value)
        case .int64(let value): return integer("int64", value)
        case .uint8(let value): return integer("uint8", value)
        case .uint16(let value): return integer("uint16", value)
        case .uint32(let value): return integer("uint32", value)
        case .uint64(let value): return integer("uint64", value)
        case .float32(let value):
            return tagged("float32", "bits", .string(hex(value.bitPattern, digits: 8)))
        case .float64(let value):
            return tagged("float64", "bits", .string(hex(value.bitPattern, digits: 16)))
        case .decimal(let value):
            return tagged(
                "decimal",
                "value",
                .string(
                    try value.decimalLexicalForm(
                        maximumUTF8Count: maximumBytes
                    )
                )
            )
        case .string(let value): return tagged("string", "value", .string(value))
        case .bytes(let value):
            return tagged("bytes", "value", .string(Base64URL.encode(value)))
        case .date(let value):
            return .object([
                ("$type", .string("date")),
                ("year", .string(String(value.year))),
                ("month", .string(String(value.month))),
                ("day", .string(String(value.day))),
            ])
        case .time(let value):
            return .object([
                ("$type", .string("time")),
                ("hour", .string(String(value.hour))),
                ("minute", .string(String(value.minute))),
                ("second", .string(String(value.second))),
                ("nanoseconds", .string(String(value.nanoseconds))),
            ])
        case .dateTime(let value):
            return .object([
                ("$type", .string("dateTime")),
                ("date", try encode(.date(value.date), depth: depth + 1)),
                ("time", try encode(.time(value.time), depth: depth + 1)),
            ])
        case .timestamp(let value):
            return .object([
                ("$type", .string("timestamp")),
                ("seconds", .string(String(value.secondsSinceUnixEpoch))),
                ("nanoseconds", .string(String(value.nanoseconds))),
            ])
        case .timeSpan(let value):
            return .object([
                ("$type", .string("timeSpan")),
                ("seconds", .string(String(value.seconds))),
                ("nanoseconds", .string(String(value.nanoseconds))),
            ])
        case .calendarPeriod(let value):
            return .object([
                ("$type", .string("calendarPeriod")),
                ("months", .string(String(value.months))),
                ("days", .string(String(value.days))),
            ])
        case .geographicPoint(let value):
            return .object([
                ("$type", .string("geographicPoint")),
                ("latitudeBits", .string(hex(value.latitude.bitPattern, digits: 16))),
                ("longitudeBits", .string(hex(value.longitude.bitPattern, digits: 16))),
            ])
        case .geographicPosition(let value):
            return .object([
                ("$type", .string("geographicPosition")),
                ("latitudeBits", .string(hex(value.point.latitude.bitPattern, digits: 16))),
                ("longitudeBits", .string(hex(value.point.longitude.bitPattern, digits: 16))),
                ("heightBits", .string(hex(value.ellipsoidalHeightInMeters.bitPattern, digits: 16))),
            ])
        case .vector(let value): return try encodeVector(value)
        case .uuid(let value): return tagged("uuid", "value", .string(value.description))
        case .array(let values):
            try requireCollection(values.count, path: "FieldValue.array")
            return tagged(
                "array",
                "value",
                .array(try values.map { try encode($0, depth: depth + 1) })
            )
        case .object(let value):
            try requireCollection(value.fields.count, path: "FieldValue.object")
            return tagged(
                "object",
                "value",
                .object(
                    try value.fields.map {
                        ($0.key, try encode($0.value, depth: depth + 1))
                    }
                )
            )
        case .reference(let value):
            return .object([
                ("$type", .string("reference")),
                ("entity", .string(value.entity)),
                ("id", encodeReferenceIdentifier(value.id)),
                ("partitions", try encode(.object(value.partitions), depth: depth + 1)),
            ])
        case .rdfTerm(let value):
            return tagged(
                "rdfTerm",
                "value",
                try encodeRDFTerm(value, depth: depth + 1)
            )
        }
    }

    func decode(
        _ node: JSONValue,
        path: String,
        depth: Int
    ) throws -> FieldValue {
        try requireDepth(depth)
        if case .number = node {
            throw SchemaJSONError.invalidValue(
                path: path,
                reason: "untagged JSON numbers are not allowed"
            )
        }
        let object = try JSONObject(node, path: path)
        let tag = try object.required("$type").string(path: object.child("$type"))
        switch tag {
        case "null":
            try object.validateKeys(["$type"])
            return .null
        case "bool":
            try object.validateKeys(["$type", "value"])
            return .bool(try object.required("value").bool(path: object.child("value")))
        case "int8": return .int8(try decodeInteger(object, tag: tag))
        case "int16": return .int16(try decodeInteger(object, tag: tag))
        case "int32": return .int32(try decodeInteger(object, tag: tag))
        case "int64": return .int64(try decodeInteger(object, tag: tag))
        case "uint8": return .uint8(try decodeInteger(object, tag: tag))
        case "uint16": return .uint16(try decodeInteger(object, tag: tag))
        case "uint32": return .uint32(try decodeInteger(object, tag: tag))
        case "uint64": return .uint64(try decodeInteger(object, tag: tag))
        case "float32": return .float32(try decodeFloat32(object))
        case "float64": return .float64(try decodeFloat64(object))
        case "decimal":
            try object.validateKeys(["$type", "value"])
            return .decimal(
                try decodeDecimal(
                    object.required("value").string(path: object.child("value")),
                    path: object.child("value")
                )
            )
        case "string":
            try object.validateKeys(["$type", "value"])
            return .string(try object.required("value").string(path: object.child("value")))
        case "bytes":
            try object.validateKeys(["$type", "value"])
            return .bytes(
                try Base64URL.decode(
                    object.required("value").string(path: object.child("value")),
                    path: object.child("value")
                )
            )
        case "date": return .date(try decodeDate(object))
        case "time": return .time(try decodeTime(object))
        case "dateTime": return .dateTime(try decodeDateTime(object, depth: depth))
        case "timestamp": return .timestamp(try decodeTimestamp(object))
        case "timeSpan": return .timeSpan(try decodeTimeSpan(object))
        case "calendarPeriod": return .calendarPeriod(try decodeCalendarPeriod(object))
        case "geographicPoint": return .geographicPoint(try decodeGeographicPoint(object))
        case "geographicPosition":
            return .geographicPosition(try decodeGeographicPosition(object))
        case "vector": return .vector(try decodeVector(object))
        case "uuid":
            try object.validateKeys(["$type", "value"])
            let value = try object.required("value").string(path: object.child("value"))
            guard let uuid = DatabaseTypes.UUID(canonicalString: value),
                  uuid.description == value else {
                throw invalid(object.child("value"), "invalid canonical UUID")
            }
            return .uuid(uuid)
        case "array":
            try object.validateKeys(["$type", "value"])
            let nodes = try object.required("value").array(path: object.child("value"))
            try requireCollection(nodes.count, path: object.child("value"))
            return .array(
                try nodes.enumerated().map {
                    try decode(
                        $0.element,
                        path: "\(object.child("value"))[\($0.offset)]",
                        depth: depth + 1
                    )
                }
            )
        case "object":
            try object.validateKeys(["$type", "value"])
            return .object(
                try decodeFieldObject(
                    object.required("value"),
                    path: object.child("value"),
                    depth: depth + 1
                )
            )
        case "reference":
            return .reference(try decodeReference(object, depth: depth + 1))
        case "rdfTerm":
            try object.validateKeys(["$type", "value"])
            return .rdfTerm(
                try decodeRDFTerm(
                    object.required("value"),
                    path: object.child("value"),
                    depth: depth + 1
                )
            )
        default:
            throw invalid(object.child("$type"), "unknown FieldValue tag '\(tag)'")
        }
    }
}

private extension FieldValueJSONCodec {
    func tagged(_ type: String) -> JSONValue {
        .object([("$type", .string(type))])
    }

    func tagged(_ type: String, _ name: String, _ value: JSONValue) -> JSONValue {
        .object([("$type", .string(type)), (name, value)])
    }

    func integer<T: FixedWidthInteger>(_ type: String, _ value: T) -> JSONValue {
        tagged(type, "value", .string(String(value)))
    }

    func hex<T: FixedWidthInteger>(_ value: T, digits: Int) -> String {
        let raw = String(value, radix: 16, uppercase: false)
        return String(repeating: "0", count: digits - raw.count) + raw
    }

    func encodeVector(_ value: Vector) throws -> JSONValue {
        let values: [JSONValue]
        let elementType: String
        switch value.elementType {
        case .int8:
            elementType = "int8"
            values = try requireVectorStorage(value.withInt8Elements { $0.map { .string(String($0)) } })
        case .int16:
            elementType = "int16"
            values = try requireVectorStorage(value.withInt16Elements { $0.map { .string(String($0)) } })
        case .int32:
            elementType = "int32"
            values = try requireVectorStorage(value.withInt32Elements { $0.map { .string(String($0)) } })
        case .int64:
            elementType = "int64"
            values = try requireVectorStorage(value.withInt64Elements { $0.map { .string(String($0)) } })
        case .uint8:
            elementType = "uint8"
            values = try requireVectorStorage(value.withUInt8Elements { $0.map { .string(String($0)) } })
        case .uint16:
            elementType = "uint16"
            values = try requireVectorStorage(value.withUInt16Elements { $0.map { .string(String($0)) } })
        case .uint32:
            elementType = "uint32"
            values = try requireVectorStorage(value.withUInt32Elements { $0.map { .string(String($0)) } })
        case .uint64:
            elementType = "uint64"
            values = try requireVectorStorage(value.withUInt64Elements { $0.map { .string(String($0)) } })
        case .float32:
            elementType = "float32"
            values = try requireVectorStorage(value.withFloat32Elements {
                $0.map { .string(hex($0.bitPattern, digits: 8)) }
            })
        case .float64:
            elementType = "float64"
            values = try requireVectorStorage(value.withFloat64Elements {
                $0.map { .string(hex($0.bitPattern, digits: 16)) }
            })
        }
        guard values.count == value.count else {
            throw invalid("FieldValue.vector", "storage type does not match element type")
        }
        try requireCollection(values.count, path: "FieldValue.vector.values")
        return .object([
            ("$type", .string("vector")),
            ("elementType", .string(elementType)),
            ("values", .array(values)),
        ])
    }

    func requireVectorStorage(_ values: [JSONValue]?) throws -> [JSONValue] {
        guard let values else {
            throw invalid("FieldValue.vector", "storage type does not match element type")
        }
        return values
    }

    func encodeReferenceIdentifier(_ value: ReferenceIdentifier) -> JSONValue {
        let kind: String
        let node: JSONValue
        switch value {
        case .bool(let value): kind = "bool"; node = .bool(value)
        case .int8(let value): kind = "int8"; node = .string(String(value))
        case .int16(let value): kind = "int16"; node = .string(String(value))
        case .int32(let value): kind = "int32"; node = .string(String(value))
        case .int64(let value): kind = "int64"; node = .string(String(value))
        case .uint8(let value): kind = "uint8"; node = .string(String(value))
        case .uint16(let value): kind = "uint16"; node = .string(String(value))
        case .uint32(let value): kind = "uint32"; node = .string(String(value))
        case .uint64(let value): kind = "uint64"; node = .string(String(value))
        case .string(let value): kind = "string"; node = .string(value)
        case .bytes(let value): kind = "bytes"; node = .string(Base64URL.encode(value))
        case .uuid(let value): kind = "uuid"; node = .string(value.description)
        case .composite(let values):
            kind = "composite"
            node = .array(values.map(encodeReferenceIdentifier))
        }
        return .object([("kind", .string(kind)), ("value", node)])
    }

    func encodeRDFTerm(_ value: RDFTerm, depth: Int) throws -> JSONValue {
        try requireDepth(depth)
        switch value {
        case .iri(let value):
            return .object([("kind", .string("iri")), ("value", .string(value.rawValue))])
        case .blankNode(let value):
            return .object([("kind", .string("blankNode")), ("value", .string(value.rawValue))])
        case .literal(let value):
            var fields: [(key: String, value: JSONValue)] = [
                ("kind", .string("literal")),
                ("lexicalForm", .string(value.lexicalForm)),
            ]
            switch value.annotation {
            case .typed(let datatype): fields.append(("datatype", .string(datatype.rawValue)))
            case .languageTagged(let language): fields.append(("language", .string(language.rawValue)))
            case .directionalLanguageTagged(let language, let direction):
                fields.append(("language", .string(language.rawValue)))
                fields.append(("direction", .string(direction.rawValue)))
            }
            return .object(fields)
        case .tripleTerm(let subject, let predicate, let object):
            return .object([
                ("kind", .string("tripleTerm")),
                ("subject", try encodeRDFTerm(subject.term, depth: depth + 1)),
                ("predicate", .string(predicate.rawValue)),
                ("object", try encodeRDFTerm(object, depth: depth + 1)),
            ])
        }
    }
}

private extension FieldValueJSONCodec {
    func decodeInteger<T: FixedWidthInteger>(
        _ object: JSONObject,
        tag: String
    ) throws -> T {
        try object.validateKeys(["$type", "value"])
        let path = object.child("value")
        let value = try object.required("value").string(path: path)
        guard isCanonicalInteger(value), let parsed = T(value) else {
            throw invalid(path, "invalid \(tag) value")
        }
        return parsed
    }

    func isCanonicalInteger(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        if value == "0" { return true }
        let bytes = Array(value.utf8)
        let digits: ArraySlice<UInt8>
        if bytes[0] == 0x2D {
            guard bytes.count > 1, bytes[1] != 0x30 else { return false }
            digits = bytes[1...]
        } else {
            guard bytes[0] != 0x30 else { return false }
            digits = bytes[...]
        }
        return digits.allSatisfy { (0x30...0x39).contains($0) }
    }

    func decodeFloat32(_ object: JSONObject) throws -> Float {
        try object.validateKeys(["$type", "bits"])
        let path = object.child("bits")
        let bits: UInt32 = try hexadecimalBits(
            object.required("bits").string(path: path),
            digits: 8,
            path: path
        )
        let value = Float(bitPattern: bits)
        guard value.isFinite else { throw invalid(path, "non-finite float32") }
        return value
    }

    func decodeFloat64(_ object: JSONObject) throws -> Double {
        try object.validateKeys(["$type", "bits"])
        let path = object.child("bits")
        let bits: UInt64 = try hexadecimalBits(
            object.required("bits").string(path: path),
            digits: 16,
            path: path
        )
        let value = Double(bitPattern: bits)
        guard value.isFinite else { throw invalid(path, "non-finite float64") }
        return value
    }

    func hexadecimalBits<T: FixedWidthInteger>(
        _ value: String,
        digits: Int,
        path: String
    ) throws -> T {
        guard value.utf8.count == digits,
              value.utf8.allSatisfy({
                  (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
              }),
              let result = T(value, radix: 16) else {
            throw invalid(path, "invalid fixed-width IEEE bit pattern")
        }
        return result
    }

    func decodeDecimal(_ value: String, path: String) throws -> ExactDecimal {
        guard !value.isEmpty else { throw invalid(path, "empty decimal") }
        var text = value[...]
        let negative = text.first == "-"
        if negative { text = text.dropFirst() }
        guard !text.isEmpty else { throw invalid(path, "invalid decimal") }
        let components = text.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count <= 2,
              !components[0].isEmpty,
              components.allSatisfy({ part in
                  part.utf8.allSatisfy { (0x30...0x39).contains($0) }
              }) else {
            throw invalid(path, "invalid decimal")
        }
        let fractional = components.count == 2 ? components[1] : Substring()
        guard components.count == 1 || !fractional.isEmpty,
              let scale = Int32(exactly: fractional.utf8.count) else {
            throw invalid(path, "invalid decimal scale")
        }
        let digits = String(components[0] + fractional)
        let signedDigits = negative ? "-" + digits : digits
        guard let coefficient = Int128(signedDigits) else {
            throw invalid(path, "decimal coefficient is out of range")
        }
        let decimal = ExactDecimal(coefficient: coefficient, scale: scale)
        let canonical = try decimal.decimalLexicalForm(maximumUTF8Count: maximumBytes)
        guard canonical == value else { throw invalid(path, "non-canonical decimal") }
        return decimal
    }

    func decodeDate(_ object: JSONObject) throws -> CivilDate {
        try object.validateKeys(["$type", "year", "month", "day"])
        return try CivilDate(
            year: integerValue(object, "year"),
            month: integerValue(object, "month"),
            day: integerValue(object, "day")
        )
    }

    func decodeTime(_ object: JSONObject) throws -> CivilTime {
        try object.validateKeys(["$type", "hour", "minute", "second", "nanoseconds"])
        return try CivilTime(
            hour: integerValue(object, "hour"),
            minute: integerValue(object, "minute"),
            second: integerValue(object, "second"),
            nanoseconds: integerValue(object, "nanoseconds")
        )
    }

    func decodeDateTime(_ object: JSONObject, depth: Int) throws -> CivilDateTime {
        try object.validateKeys(["$type", "date", "time"])
        guard case .date(let date) = try decode(
            object.required("date"),
            path: object.child("date"),
            depth: depth + 1
        ), case .time(let time) = try decode(
            object.required("time"),
            path: object.child("time"),
            depth: depth + 1
        ) else {
            throw invalid(object.path, "dateTime requires tagged date and time")
        }
        return CivilDateTime(date: date, time: time)
    }

    func decodeTimestamp(_ object: JSONObject) throws -> Timestamp {
        try object.validateKeys(["$type", "seconds", "nanoseconds"])
        return try Timestamp(
            secondsSinceUnixEpoch: integerValue(object, "seconds"),
            nanoseconds: integerValue(object, "nanoseconds")
        )
    }

    func decodeTimeSpan(_ object: JSONObject) throws -> TimeSpan {
        try object.validateKeys(["$type", "seconds", "nanoseconds"])
        return try TimeSpan(
            seconds: integerValue(object, "seconds"),
            nanoseconds: integerValue(object, "nanoseconds")
        )
    }

    func decodeCalendarPeriod(_ object: JSONObject) throws -> CalendarPeriod {
        try object.validateKeys(["$type", "months", "days"])
        return CalendarPeriod(
            months: try integerValue(object, "months"),
            days: try integerValue(object, "days")
        )
    }

    func decodeGeographicPoint(_ object: JSONObject) throws -> GeographicPoint {
        try object.validateKeys(["$type", "latitudeBits", "longitudeBits"])
        return try GeographicPoint(
            latitude: doubleBits(object, "latitudeBits"),
            longitude: doubleBits(object, "longitudeBits")
        )
    }

    func decodeGeographicPosition(_ object: JSONObject) throws -> GeographicPosition {
        try object.validateKeys(["$type", "latitudeBits", "longitudeBits", "heightBits"])
        return try GeographicPosition(
            latitude: doubleBits(object, "latitudeBits"),
            longitude: doubleBits(object, "longitudeBits"),
            ellipsoidalHeightInMeters: doubleBits(object, "heightBits")
        )
    }

    func doubleBits(_ object: JSONObject, _ name: String) throws -> Double {
        let path = object.child(name)
        let bits: UInt64 = try hexadecimalBits(
            object.required(name).string(path: path),
            digits: 16,
            path: path
        )
        let value = Double(bitPattern: bits)
        guard value.isFinite else { throw invalid(path, "non-finite coordinate") }
        return value
    }

    func decodeVector(_ object: JSONObject) throws -> Vector {
        try object.validateKeys(["$type", "elementType", "values"])
        let typePath = object.child("elementType")
        let valuesPath = object.child("values")
        let type = try object.required("elementType").string(path: typePath)
        let nodes = try object.required("values").array(path: valuesPath)
        try requireCollection(nodes.count, path: valuesPath)
        let strings = try nodes.enumerated().map {
            try $0.element.string(path: "\(valuesPath)[\($0.offset)]")
        }
        switch type {
        case "int8": return Vector(int8: try strings.map { try parseInteger($0, path: valuesPath) })
        case "int16": return Vector(int16: try strings.map { try parseInteger($0, path: valuesPath) })
        case "int32": return Vector(int32: try strings.map { try parseInteger($0, path: valuesPath) })
        case "int64": return Vector(int64: try strings.map { try parseInteger($0, path: valuesPath) })
        case "uint8": return Vector(uint8: try strings.map { try parseInteger($0, path: valuesPath) })
        case "uint16": return Vector(uint16: try strings.map { try parseInteger($0, path: valuesPath) })
        case "uint32": return Vector(uint32: try strings.map { try parseInteger($0, path: valuesPath) })
        case "uint64": return Vector(uint64: try strings.map { try parseInteger($0, path: valuesPath) })
        case "float32":
            return try Vector(float32: strings.map {
                let bits: UInt32 = try hexadecimalBits($0, digits: 8, path: valuesPath)
                let value = Float(bitPattern: bits)
                guard value.isFinite else { throw invalid(valuesPath, "non-finite vector value") }
                return value
            })
        case "float64":
            return try Vector(float64: strings.map {
                let bits: UInt64 = try hexadecimalBits($0, digits: 16, path: valuesPath)
                let value = Double(bitPattern: bits)
                guard value.isFinite else { throw invalid(valuesPath, "non-finite vector value") }
                return value
            })
        default: throw invalid(typePath, "unknown vector element type '\(type)'")
        }
    }

    func parseInteger<T: FixedWidthInteger>(_ value: String, path: String) throws -> T {
        guard isCanonicalInteger(value), let parsed = T(value) else {
            throw invalid(path, "invalid integer")
        }
        return parsed
    }

    func integerValue<T: FixedWidthInteger>(
        _ object: JSONObject,
        _ name: String
    ) throws -> T {
        let path = object.child(name)
        return try parseInteger(object.required(name).string(path: path), path: path)
    }

    func decodeFieldObject(
        _ node: JSONValue,
        path: String,
        depth: Int
    ) throws -> FieldObject {
        guard case .object(let fields) = node else {
            throw SchemaJSONError.typeMismatch(path: path, expected: "an object")
        }
        try requireCollection(fields.count, path: path)
        return try FieldObject(
            fields.enumerated().map {
                (
                    $0.element.key,
                    try decode(
                        $0.element.value,
                        path: "\(path).\($0.element.key)",
                        depth: depth
                    )
                )
            }
        )
    }

    func decodeReference(_ object: JSONObject, depth: Int) throws -> EntityReference {
        try object.validateKeys(["$type", "entity", "id", "partitions"])
        let partitions: FieldObject
        if let node = object.optional("partitions") {
            guard case .object(let value) = try decode(
                node,
                path: object.child("partitions"),
                depth: depth
            ) else {
                throw invalid(object.child("partitions"), "must be a tagged object")
            }
            partitions = value
        } else {
            partitions = FieldObject()
        }
        return try EntityReference(
            entity: object.required("entity").string(path: object.child("entity")),
            id: decodeReferenceIdentifier(
                object.required("id"),
                path: object.child("id"),
                depth: depth
            ),
            partitions: partitions
        )
    }

    func decodeReferenceIdentifier(
        _ node: JSONValue,
        path: String,
        depth: Int
    ) throws -> ReferenceIdentifier {
        try requireDepth(depth)
        let object = try JSONObject(node, path: path)
        try object.validateKeys(["kind", "value"])
        let kind = try object.required("kind").string(path: object.child("kind"))
        let value = try object.required("value")
        let valuePath = object.child("value")
        switch kind {
        case "bool": return .bool(try value.bool(path: valuePath))
        case "int8": return .int8(try parseInteger(value.string(path: valuePath), path: valuePath))
        case "int16": return .int16(try parseInteger(value.string(path: valuePath), path: valuePath))
        case "int32": return .int32(try parseInteger(value.string(path: valuePath), path: valuePath))
        case "int64": return .int64(try parseInteger(value.string(path: valuePath), path: valuePath))
        case "uint8": return .uint8(try parseInteger(value.string(path: valuePath), path: valuePath))
        case "uint16": return .uint16(try parseInteger(value.string(path: valuePath), path: valuePath))
        case "uint32": return .uint32(try parseInteger(value.string(path: valuePath), path: valuePath))
        case "uint64": return .uint64(try parseInteger(value.string(path: valuePath), path: valuePath))
        case "string": return .string(try value.string(path: valuePath))
        case "bytes": return .bytes(try Base64URL.decode(value.string(path: valuePath), path: valuePath))
        case "uuid":
            let string = try value.string(path: valuePath)
            guard let uuid = DatabaseTypes.UUID(canonicalString: string),
                  uuid.description == string else {
                throw invalid(valuePath, "invalid canonical UUID")
            }
            return .uuid(uuid)
        case "composite":
            let values = try value.array(path: valuePath)
            try requireCollection(values.count, path: valuePath)
            return .composite(
                try values.enumerated().map {
                    try decodeReferenceIdentifier(
                        $0.element,
                        path: "\(valuePath)[\($0.offset)]",
                        depth: depth + 1
                    )
                }
            )
        default: throw invalid(object.child("kind"), "unknown reference identifier kind '\(kind)'")
        }
    }

    func decodeRDFTerm(_ node: JSONValue, path: String, depth: Int) throws -> RDFTerm {
        try requireDepth(depth)
        let object = try JSONObject(node, path: path)
        let kind = try object.required("kind").string(path: object.child("kind"))
        switch kind {
        case "iri":
            try object.validateKeys(["kind", "value"])
            return .iri(try RDFIRI(object.required("value").string(path: object.child("value"))))
        case "blankNode":
            try object.validateKeys(["kind", "value"])
            return .blankNode(
                try RDFBlankNodeIdentifier(
                    object.required("value").string(path: object.child("value"))
                )
            )
        case "literal":
            try object.validateKeys(["kind", "lexicalForm", "datatype", "language", "direction"])
            let lexical = try object.required("lexicalForm").string(path: object.child("lexicalForm"))
            if let datatype = object.optional("datatype") {
                guard object.optional("language") == nil,
                      object.optional("direction") == nil else {
                    throw invalid(path, "typed RDF literal cannot have language")
                }
                return .literal(
                    try RDFLiteral(
                        lexicalForm: lexical,
                        datatype: datatype.string(path: object.child("datatype"))
                    )
                )
            }
            let language = try RDFLanguageTag(
                object.required("language").string(path: object.child("language"))
            )
            if let direction = object.optional("direction") {
                guard let value = RDFDirection(
                    rawValue: try direction.string(path: object.child("direction"))
                ) else {
                    throw invalid(object.child("direction"), "invalid RDF base direction")
                }
                return .literal(
                    RDFLiteral(lexicalForm: lexical, language: language, direction: value)
                )
            }
            return .literal(RDFLiteral(lexicalForm: lexical, language: language))
        case "tripleTerm":
            try object.validateKeys(["kind", "subject", "predicate", "object"])
            let subjectTerm = try decodeRDFTerm(
                object.required("subject"),
                path: object.child("subject"),
                depth: depth + 1
            )
            let subject: RDFSubject
            switch subjectTerm {
            case .iri(let value): subject = .iri(value)
            case .blankNode(let value): subject = .blankNode(value)
            case .literal, .tripleTerm:
                throw invalid(object.child("subject"), "RDF triple subject must be an IRI or blank node")
            }
            return .tripleTerm(
                subject: subject,
                predicate: try RDFPredicateIRI(
                    object.required("predicate").string(path: object.child("predicate"))
                ),
                object: try decodeRDFTerm(
                    object.required("object"),
                    path: object.child("object"),
                    depth: depth + 1
                )
            )
        default: throw invalid(object.child("kind"), "unknown RDF term kind '\(kind)'")
        }
    }
}

private extension FieldValueJSONCodec {
    func requireDepth(_ depth: Int) throws {
        guard depth <= maximumDepth else {
            throw SchemaJSONError.nestingTooDeep(maximum: maximumDepth)
        }
    }

    func requireCollection(_ count: Int, path: String) throws {
        guard count <= maximumCollectionCount else {
            throw SchemaJSONError.collectionTooLarge(
                path: path,
                actual: count,
                maximum: maximumCollectionCount
            )
        }
    }

    func invalid(_ path: String, _ reason: String) -> SchemaJSONError {
        .invalidValue(path: path, reason: reason)
    }
}
