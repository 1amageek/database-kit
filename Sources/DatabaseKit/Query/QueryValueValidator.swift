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
                 (.varchar, .primitive(.string)), (.date, .primitive(.date)),
                 (.time(false, _), .primitive(.time)),
                 (.timestamp(false, _), .primitive(.dateTime)),
                 (.timestamp(true, _), .primitive(.timestamp)),
                 (.binary, .primitive(.bytes)), (.varbinary, .primitive(.bytes)),
                 (.blob, .primitive(.bytes)), (.uuid, .primitive(.uuid)),
                 (.json, .json), (.jsonb, .jsonb), (.interval, .interval): return true
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
            default: return false
            }
        }
    }

    private static func isResolved(_ type: DataType) -> Bool {
        switch type {
        case .custom: return false
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
        case .array(let element):
            if case .array = element { return false }
            return isResolved(element)
        default: return true
        }
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

    private enum Visit {
        case query(QueryValue, UInt64)
        case primitive(FieldValue, UInt64)
        case arrayElements([QueryValue], index: Int, depth: UInt64)
    }

    private static func measure(_ value: QueryValue,
                                limits: QueryValueLimits?) throws(QueryValueError) -> QueryValueFootprint {
        var stack: [Visit] = [.query(value, 1)]
        var nodes: UInt64 = 0
        var elements: UInt64 = 0
        var bytes: UInt64 = 0
        var depth: UInt64 = 0
        func added(_ lhs: UInt64, _ rhs: UInt64) throws(QueryValueError) -> UInt64 {
            let result = lhs.addingReportingOverflow(rhs)
            guard !result.overflow else { throw .arithmeticOverflow }
            return result.partialValue
        }
        while let visit = stack.popLast() {
            let nodeDepth: UInt64
            var arrayChildren: (values: [QueryValue], depth: UInt64)?
            switch visit {
            case .query(let value, let current):
                nodeDepth = current
                switch value {
                case .primitive(let value): stack.append(.primitive(value, current)); continue
                case .numeric, .interval: nodes = try added(nodes, 1)
                case .json(let value):
                    let footprint = try value.measure()
                    nodes = try added(nodes, footprint.nodeCount)
                    elements = try added(elements, footprint.collectionElementCount)
                    bytes = try added(bytes, footprint.retainedByteCount)
                    depth = max(depth, try added(current - 1, footprint.maximumNestingDepth))
                case .jsonb(let value):
                    let footprint = try value.measure()
                    nodes = try added(nodes, footprint.nodeCount)
                    elements = try added(elements, footprint.collectionElementCount)
                    bytes = try added(bytes, footprint.retainedByteCount)
                    depth = max(depth, try added(current - 1, footprint.maximumNestingDepth))
                case .array(let array):
                    nodes = try added(nodes, 1)
                    elements = try added(elements, UInt64(array.elements.count))
                    if !array.elements.isEmpty {
                        arrayChildren = (array.elements, try added(current, 1))
                    }
                }
            case .primitive(let value, let current):
                nodeDepth = current
                var meter = QueryFieldStorageMeter(limits: limits)
                try meter.field(value, depth: current)
                nodes = try added(nodes, meter.footprint.valueNodes)
                elements = try added(elements, try added(meter.footprint.objectEntries, meter.footprint.arrayElements))
                bytes = try added(bytes, meter.retainedByteCount)
                depth = max(depth, meter.footprint.maximumDepth)
            case .arrayElements(let values, let index, let childDepth):
                if index + 1 < values.count {
                    stack.append(.arrayElements(values, index: index + 1, depth: childDepth))
                }
                stack.append(.query(values[index], childDepth))
                continue
            }
            depth = max(depth, nodeDepth)
            if let limits {
                try QueryValueFootprint(nodeCount: nodes, collectionElementCount: elements,
                                        retainedByteCount: bytes, maximumNestingDepth: depth)
                    .validate(limits: limits)
            }
            if let arrayChildren {
                // Admit collection counts before retaining one cursor, never one visit per child.
                stack.append(.arrayElements(arrayChildren.values, index: 0, depth: arrayChildren.depth))
            }
        }
        return QueryValueFootprint(nodeCount: nodes, collectionElementCount: elements,
                                   retainedByteCount: bytes, maximumNestingDepth: depth)
    }
}
