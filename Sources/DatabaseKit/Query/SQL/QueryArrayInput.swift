import DatabaseTypes

/// Owned PostgreSQL array text and its flat shape index. Scalar interpretation
/// belongs to the selected caller; only a requested cell is materialized.
public struct QueryArrayInput: Sendable {
    private let bytes: ByteString
    private let cells: [Cell]
    public let dimensions: [QueryArrayDimension]
    public let retainedByteCount: UInt64
    public var count: Int { cells.count }

    private struct Cell: Sendable {
        let range: Range<Int>
        let decodedCount: Int
        let escaped: Bool
        let isNull: Bool
    }

    public init(sqlLexicalForm: String, limits: QueryValueLimits) throws(QueryValueError) {
        try QueryJSONParser.check(UInt64(sqlLexicalForm.utf8.count), maximum: limits.maximumRetainedBytes,
                                  resource: "retainedBytes")
        // The immutable final byte owner is copied once from the String boundary.
        let bytes = ByteString(utf8: sqlLexicalForm)
        let parsed = try bytes.withUnsafeBytes { input in
            Result<(cells: [Cell], dimensions: [QueryArrayDimension], retained: UInt64), QueryValueError> {
                () throws(QueryValueError) in
                var parser = Parser(input: input, limits: limits)
                let dimensions = try parser.parse()
                let retained = try Self.retention(inputCount: input.count, cells: parser.cells,
                                                  dimensions: dimensions)
                try QueryJSONParser.check(retained, maximum: limits.maximumRetainedBytes, resource: "retainedBytes")
                return (parser.cells, dimensions, retained)
            }
        }.get()
        self.bytes = bytes
        cells = parsed.cells
        dimensions = parsed.dimensions
        retainedByteCount = parsed.retained
    }

    /// Zero-based flat cell lookup; nil means SQL NULL, never an invalid index.
    public func elementText(at index: Int) throws(QueryValueError) -> String? {
        guard cells.indices.contains(index) else { throw .invalidArrayInputIndex(index: index, count: count) }
        let cell = cells[index]
        if cell.isNull { return nil }
        return bytes.withUnsafeBytes { input in
            if !cell.escaped { return String(decoding: input[cell.range], as: UTF8.self) }
            // Existing scalar input APIs require an independent String. Allocate
            // only this requested cell, never an eager array of decoded strings.
            return String(unsafeUninitializedCapacity: cell.decodedCount) { destination in
                var cursor = cell.range.lowerBound
                var written = 0
                while cursor < cell.range.upperBound {
                    if input[cursor] == 92 { cursor += 1 }
                    destination[written] = input[cursor]
                    written += 1
                    cursor += 1
                }
                return written
            }
        }
    }

    private static func retention(inputCount: Int, cells: [Cell], dimensions: [QueryArrayDimension])
        throws(QueryValueError) -> UInt64 {
        var bytes = UInt64(inputCount)
        for (capacity, stride, container) in [
            (cells.capacity, MemoryLayout<Cell>.stride, MemoryLayout<[Cell]>.stride),
            (dimensions.capacity, MemoryLayout<QueryArrayDimension>.stride, MemoryLayout<[QueryArrayDimension]>.stride),
        ] {
            let slots = UInt64(capacity).multipliedReportingOverflow(by: UInt64(stride))
            let sum = bytes.addingReportingOverflow(slots.partialValue)
            let total = sum.partialValue.addingReportingOverflow(UInt64(container))
            guard !slots.overflow, !sum.overflow, !total.overflow else { throw .arithmeticOverflow }
            bytes = total.partialValue
        }
        return bytes
    }

    /// Extracted from QueryAST's SQLArrayInput shape grammar. The raw borrow is
    /// synchronous and bounded by parse(); no pointer enters the owned result.
    private struct Parser {
        let input: UnsafeRawBufferPointer
        let limits: QueryValueLimits
        var index = 0
        var cells: [Cell] = []
        var peek: UInt8? { index < input.count ? input[index] : nil }
        func isSpace(_ byte: UInt8) -> Bool { byte == 32 || (9...13).contains(byte) }
        func invalid(_ reason: String) -> QueryValueError { .malformedArrayInput(offset: UInt64(index), reason: reason) }
        mutating func spaces() { while let byte = peek, isSpace(byte) { index += 1 } }
        mutating func consume(_ byte: UInt8) -> Bool {
            guard peek == byte else { return false }
            index += 1
            return true
        }
        mutating func require(_ byte: UInt8) throws(QueryValueError) {
            guard consume(byte) else { throw invalid("Malformed PostgreSQL array input") }
        }

        mutating func parse() throws(QueryValueError) -> [QueryArrayDimension] {
            try QueryJSONParser.check(1, maximum: limits.maximumTotalNodes, resource: "nodes")
            try QueryJSONParser.check(1, maximum: limits.maximumNestingDepth, resource: "depth")
            spaces()
            var declared: [(Int32, Int32)] = []
            while consume(91) {
                guard declared.count < 6 else { throw invalid("Too many array dimensions") }
                let lower = try bound(until: 58)
                let upper = try bound(until: 93)
                guard upper >= lower, upper < Int32.max,
                      let length = Int32(exactly: Int64(upper) - Int64(lower) + 1) else {
                    throw invalid("Invalid array bounds")
                }
                declared.append((lower, length))
            }
            if !declared.isEmpty { try require(61) }
            let shape = try group(depth: 1)
            spaces()
            guard index == input.count else { throw invalid("Trailing array input") }
            guard declared.isEmpty || shape == declared.map({ Int($0.1) }) else {
                throw invalid("Array bounds disagree with shape")
            }
            var dimensions: [QueryArrayDimension] = []
            for (offset, length) in shape.enumerated() {
                guard let length = Int32(exactly: length) else { throw invalid("Array dimension out of range") }
                dimensions.append(try QueryArrayDimension(lowerBound: declared.isEmpty ? 1 : declared[offset].0,
                                                          length: length))
            }
            return dimensions
        }

        mutating func bound(until terminator: UInt8) throws(QueryValueError) -> Int32 {
            let start = index
            while let byte = peek, byte != terminator { index += 1 }
            guard let value = Int32(String(decoding: input[start..<index], as: UTF8.self)) else {
                throw invalid("Invalid array bound")
            }
            try require(terminator)
            return value
        }

        mutating func group(depth: UInt64) throws(QueryValueError) -> [Int] {
            guard depth <= 6 else { throw invalid("Too many array dimensions") }
            try QueryJSONParser.check(depth, maximum: limits.maximumNestingDepth, resource: "depth")
            spaces()
            try require(123)
            spaces()
            if consume(125) {
                guard depth == 1 else { throw invalid("Empty nested array dimension") }
                return []
            }
            let nested = peek == 123
            var childShape: [Int]?
            var count = 0
            repeat {
                spaces()
                guard (peek == 123) == nested else { throw invalid("Mixed scalar and nested array elements") }
                if nested {
                    let shape = try group(depth: depth + 1)
                    if let childShape, childShape != shape { throw invalid("Ragged array shape") }
                    childShape = shape
                } else {
                    try QueryJSONParser.check(UInt64(cells.count) + 1, maximum: limits.maximumCollectionElements,
                                              resource: "collectionElements")
                    try QueryJSONParser.check(UInt64(cells.count) + 2, maximum: limits.maximumTotalNodes, resource: "nodes")
                    try QueryJSONParser.check(2, maximum: limits.maximumNestingDepth, resource: "depth")
                    let cell = try scalar()
                    cells.append(cell)
                    // Reconcile real metadata capacity before indexing another cell.
                    let retained = try QueryArrayInput.retention(inputCount: input.count, cells: cells, dimensions: [])
                    try QueryJSONParser.check(retained, maximum: limits.maximumRetainedBytes, resource: "retainedBytes")
                }
                count += 1
                try QueryJSONParser.check(UInt64(count), maximum: limits.maximumCollectionElements, resource: "collectionElements")
                spaces()
                if !consume(44) { break }
            } while true
            try require(125)
            return [count] + (childShape ?? [])
        }

        mutating func scalar() throws(QueryValueError) -> Cell {
            spaces()
            let quoted = consume(34)
            let start = index
            var decodedCount = 0
            var escaped = false
            var closed = false
            var contentEnd = index
            var lastNonSpaceEnd = index
            var lastNonSpaceCount = 0
            while let byte = peek {
                if quoted, byte == 34 { contentEnd = index; index += 1; closed = true; break }
                if !quoted, byte == 44 || byte == 125 { contentEnd = index; break }
                index += 1
                let decoded: UInt8
                if byte == 92 {
                    guard let next = peek else { throw invalid("Unterminated array escape") }
                    decoded = next
                    index += 1
                    escaped = true
                } else {
                    guard quoted || byte != 34 && byte != 123 else { throw invalid("Invalid unquoted array cell") }
                    decoded = byte
                }
                decodedCount += 1
                contentEnd = index
                // Escaped whitespace is content; only unescaped exterior
                // whitespace may be trimmed from an unquoted cell.
                if byte == 92 || !isSpace(decoded) { lastNonSpaceEnd = index; lastNonSpaceCount = decodedCount }
            }
            if quoted {
                guard closed else { throw invalid("Unterminated quoted array cell") }
            } else {
                contentEnd = lastNonSpaceEnd
                decodedCount = lastNonSpaceCount
                guard contentEnd > start else { throw invalid("Empty unquoted array cell") }
                if !escaped, decodedCount == 4,
                   input[start] == 78 || input[start] == 110,
                   input[start + 1] == 85 || input[start + 1] == 117,
                   input[start + 2] == 76 || input[start + 2] == 108,
                   input[start + 3] == 76 || input[start + 3] == 108 {
                    return Cell(range: start..<contentEnd, decodedCount: 0, escaped: false, isNull: true)
                }
            }
            try QueryJSONParser.check(UInt64(decodedCount), maximum: limits.maximumRetainedBytes, resource: "retainedBytes")
            return Cell(range: start..<contentEnd, decodedCount: decodedCount, escaped: escaped, isNull: false)
        }
    }
}
