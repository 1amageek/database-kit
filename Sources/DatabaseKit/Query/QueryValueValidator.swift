import DatabaseTypes

public enum QueryValueValidator {
    public static func validate(_ value: QueryValue, type: QueryColumnType? = nil,
                                limits: QueryValueLimits) throws(QueryValueError) {
        if let type, !accepts(value, type: type) { throw .incompatibleType }
        try measure(value, limits: limits).validate(limits: limits)
    }

    public static func accepts(_ value: QueryValue, type: QueryColumnType) -> Bool {
        if case .sql(let type) = type, !isResolved(type) { return false }
        if value.isNull { return true }
        switch type {
        case .primitive(let kind, let isArray):
            guard case .primitive(let primitive) = value else { return false }
            if isArray {
                guard case .array(let elements) = primitive else { return false }
                return elements.allSatisfy {
                    if case .null = $0 { return true }
                    return acceptsPrimitive($0, kind: kind)
                }
            }
            return acceptsPrimitive(primitive, kind: kind)
        case .sql(let type):
            switch (type, value) {
            case (.boolean, .primitive(.bool)), (.smallint, .primitive(.int16)),
                 (.integer, .primitive(.int32)), (.bigint, .primitive(.int64)),
                 (.text, .primitive(.string)), (.char, .primitive(.string)),
                 (.varchar, .primitive(.string)),
                 (.binary, .primitive(.bytes)), (.varbinary, .primitive(.bytes)),
                 (.blob, .primitive(.bytes)), (.uuid, .primitive(.uuid)),
                 (.json, .json), (.jsonb, .jsonb): return true
            case (.date, .primitive(.date(let value))): return acceptsSQLDate(value)
            case (.date, .dateInfinity): return true
            case (.time(false, let precision), .primitive(.time(let value))):
                return value.nanoseconds.isMultiple(of: 1000)
                    && aligned(timeMicroseconds(value), precision: precision)
            case (.time(false, let precision), .time(let value)):
                return aligned(value.microsecondsSinceMidnight, precision: precision)
            case (.time(true, let precision), .timeWithTimeZone(let value)):
                return aligned(value.time.microsecondsSinceMidnight, precision: precision)
            case (.timestamp(false, let precision), .primitive(.dateTime(let value))):
                guard value.time.nanoseconds.isMultiple(of: 1000) else { return false }
                let micros = Int128(dateDays(value.date)) * 86_400_000_000
                    + Int128(timeMicroseconds(value.time))
                return acceptsSQLTimestamp(micros, precision: precision)
            case (.timestamp(true, let precision), .primitive(.timestamp(let value))):
                guard value.nanoseconds.isMultiple(of: 1000) else { return false }
                let micros = (Int128(value.secondsSinceUnixEpoch) - 946_684_800) * 1_000_000
                    + Int128(value.nanoseconds / 1000)
                return acceptsSQLTimestamp(micros, precision: precision)
            case (.timestamp(let zone, _), .timestampInfinity(_, let valueZone)):
                return zone == valueZone
            case (.interval(let fields, let precision), .interval(let value)):
                guard aligned(value.microseconds, precision: precision) else { return false }
                switch fields {
                case .year: return value.period.months.isMultiple(of: 12)
                    && value.period.days == 0 && value.microseconds == 0
                case .month, .yearToMonth: return value.period.days == 0 && value.microseconds == 0
                case .day: return value.microseconds == 0
                case .hour, .dayToHour: return value.microseconds.isMultiple(of: 3_600_000_000)
                case .minute, .dayToMinute, .hourToMinute: return value.microseconds.isMultiple(of: 60_000_000)
                case .none, .second, .dayToSecond, .hourToSecond, .minuteToSecond: return true
                }
            case (.interval, .intervalInfinity): return true
            case (.real, .primitive(.float32(let value))): return value.isFinite
            case (.doublePrecision, .primitive(.float64(let value))): return value.isFinite
            case (.decimal(let precision, let scale), .numeric(let numeric)):
                guard precision == nil || (1...38).contains(precision!),
                      scale == nil || (-1000...1000).contains(scale!) else { return false }
                guard let scale else { return true }
                guard numeric.value.coefficient == 0 || numeric.value.scale <= Int32(scale),
                      numeric.displayScale == max(0, Int32(scale)) else { return false }
                guard let precision, numeric.value.coefficient != 0 else { return true }
                var digits = 1
                var magnitude = numeric.value.coefficient.magnitude
                while magnitude >= 10 { magnitude /= 10; digits += 1 }
                return Int64(digits) + Int64(scale) - Int64(numeric.value.scale) <= Int64(precision)
            case (.decimal(let precision, let scale), .primitive(.decimal(let decimal))):
                guard let numeric = tryNumeric(decimal) else { return false }
                return accepts(.numeric(numeric), type: .sql(.decimal(precision: precision, scale: scale)))
            case (.array(let elementType), .array(let array)): return elementType == array.elementType
            case (.composite(let type), .composite(let value)): return type == value.type
            default: return false
            }
        }
    }

    private static func isResolved(_ type: DataType) -> Bool {
        switch type {
        case .custom: return false
        case .composite: return true
        case .decimal(let precision, let scale):
            if let precision, !(1...38).contains(precision) { return false }
            if let scale, precision == nil || !(-1000...1000).contains(scale) { return false }
            return true
        case .char(let length), .varchar(let length):
            return length == nil || (1...10_485_760).contains(length!)
        case .binary(let length), .varbinary(let length):
            return length == nil || length! > 0
        case .time(_, let precision), .timestamp(_, let precision):
            return precision == nil || (0...6).contains(precision!)
        case .interval(let fields, let precision):
            guard precision == nil || (0...6).contains(precision!) else { return false }
            if precision != nil, let fields {
                switch fields {
                case .second, .dayToSecond, .hourToSecond, .minuteToSecond: break
                default: return false
                }
            }
            return true
        case .array(let element):
            if case .array = element { return false }
            return isResolved(element)
        default: return true
        }
    }

    private static func aligned<T: BinaryInteger>(_ microseconds: T, precision: Int?) -> Bool {
        var quantum: T = 1
        for _ in 0..<(6 - (precision ?? 6)) { quantum *= 10 }
        return microseconds.isMultiple(of: quantum)
    }

    private static func timeMicroseconds(_ time: CivilTime) -> Int64 {
        (Int64(time.hour) * 3600 + Int64(time.minute) * 60 + Int64(time.second))
            * 1_000_000 + Int64(time.nanoseconds / 1000)
    }

    /// Proleptic Gregorian days from 2000-01-01; Int64 covers every Int32 year.
    private static func dateDays(_ date: CivilDate) -> Int64 {
        let year = Int64(date.year) - (date.month <= 2 ? 1 : 0)
        let era = (year >= 0 ? year : year - 399) / 400
        let yearOfEra = year - era * 400
        let month = Int64(date.month) + (date.month > 2 ? -3 : 9)
        let dayOfYear = (153 * month + 2) / 5 + Int64(date.day) - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 730_425
    }

    private static func acceptsSQLDate(_ date: CivilDate) -> Bool {
        let days = dateDays(date)
        return days >= -2_451_545 && days < 2_145_031_949
    }

    private static func acceptsSQLTimestamp(_ microseconds: Int128, precision: Int?) -> Bool {
        microseconds >= -211_813_488_000_000_000
            && microseconds < 9_223_371_331_200_000_000
            && aligned(microseconds, precision: precision)
    }

    private static func tryNumeric(_ value: ExactDecimal) -> QueryNumericValue? {
        do { return try QueryNumericValue(value: value, displayScale: max(0, value.scale)) }
        catch { return nil }
    }

    private static func acceptsPrimitive(_ value: FieldValue, kind: FieldSchemaType) -> Bool {
        switch (kind, value) {
        case (.bool, .bool), (.int8, .int8), (.int16, .int16), (.int32, .int32),
             (.int64, .int64), (.uint8, .uint8), (.uint16, .uint16),
             (.uint32, .uint32), (.uint64, .uint64), (.float32, .float32),
             (.float64, .float64), (.decimal, .decimal), (.string, .string),
             (.bytes, .bytes), (.date, .date), (.time, .time), (.dateTime, .dateTime),
             (.timestamp, .timestamp), (.timeSpan, .timeSpan), (.calendarPeriod, .calendarPeriod),
             (.geographicPoint, .geographicPoint), (.geographicPosition, .geographicPosition),
             (.vector, .vector), (.uuid, .uuid), (.object, .object), (.nested, .object),
             (.rdfTerm, .rdfTerm), (.reference, .reference), (.enum, .string), (.enum, .int64): return true
        default: return false
        }
    }

    public static func measure(_ value: QueryValue) throws(QueryValueError) -> QueryValueFootprint {
        try measure(value, limits: nil)
    }

    private static func measure(_ value: QueryValue,
                                limits: QueryValueLimits?) throws(QueryValueError) -> QueryValueFootprint {
        let result: QueryValueFootprint
        switch value {
        case .array(let value): result = try value.storage.measure(value.index)
        case .composite(let value): result = try value.storage.measure(value.index)
        case .primitive(let value):
            var meter = QueryFieldStorageMeter(limits: limits)
            try meter.field(value, depth: 1)
            result = QueryValueFootprint(nodeCount: meter.footprint.valueNodes,
                collectionElementCount: try QueryValueAccounting.add(meter.footprint.objectEntries, meter.footprint.arrayElements),
                retainedByteCount: meter.retainedByteCount, maximumNestingDepth: meter.footprint.maximumDepth)
        case .json(let value): result = try value.measure()
        case .jsonb(let value): result = try value.measure()
        case .numeric, .interval, .time, .timeWithTimeZone, .dateInfinity, .timestampInfinity, .intervalInfinity:
            result = QueryValueFootprint(nodeCount: 1, collectionElementCount: 0, retainedByteCount: 0, maximumNestingDepth: 1)
        }
        if let limits { try result.validate(limits: limits) }
        return result
    }
}
