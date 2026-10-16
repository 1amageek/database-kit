import DatabaseTypes

/// Structural edges are indices; no record retains a public descriptor view.
final class QueryTypeStorage: Sendable {
    enum Kind: Sendable, Hashable {
        case boolean
        case smallint
        case integer
        case bigint
        case real
        case doublePrecision
        case decimal(precision: Int?, scale: Int?)
        case char(length: Int?)
        case varchar(length: Int?)
        case text
        case date
        case time(withTimeZone: Bool, precision: Int?)
        case timestamp(withTimeZone: Bool, precision: Int?)
        case interval(fields: SQLIntervalFields?, precision: Int?)
        case binary(length: Int?)
        case varbinary(length: Int?)
        case blob
        case json
        case jsonb
        case uuid
        case primitive(FieldSchemaType, Bool)
        case array(Int)
        case composite(Range<Int>)
    }

    struct Record: Sendable {
        let kind: Kind
        let logical: QueryValueFootprint
    }

    struct Column: Sendable {
        let number: UInt32
        let name: String
        var type: Int
        let isNullable: Bool
    }

    let records: [Record]
    let columns: [Column]
    let footprint: QueryTypeStorageFootprint

    init(records: [Record], columns: [Column], footprint: QueryTypeStorageFootprint) {
        self.records = records
        self.columns = columns
        self.footprint = footprint
    }

    func type(at index: Int) -> QueryColumnType {
        switch records[index].kind {
        case .primitive(let kind, let array): return .primitive(kind, isArray: array)
        case .array(let child): return .sql(.array(sqlLeaf(at: child)))
        default: return .sql(sqlLeaf(at: index))
        }
    }

    private func sqlLeaf(at index: Int) -> DataType {
        switch records[index].kind {
        case .boolean: return .boolean
        case .smallint: return .smallint
        case .integer: return .integer
        case .bigint: return .bigint
        case .real: return .real
        case .doublePrecision: return .doublePrecision
        case .decimal(let precision, let scale): return .decimal(precision: precision, scale: scale)
        case .char(let length): return .char(length: length)
        case .varchar(let length): return .varchar(length: length)
        case .text: return .text
        case .date: return .date
        case .time(let withTimeZone, let precision): return .time(withTimeZone: withTimeZone, precision: precision)
        case .timestamp(let withTimeZone, let precision): return .timestamp(withTimeZone: withTimeZone, precision: precision)
        case .interval(let fields, let precision): return .interval(fields: fields, precision: precision)
        case .binary(let length): return .binary(length: length)
        case .varbinary(let length): return .varbinary(length: length)
        case .blob: return .blob
        case .json: return .json
        case .jsonb: return .jsonb
        case .uuid: return .uuid
        case .composite: return .composite(QueryCompositeType(storage: self, index: index))
        case .array, .primitive: preconditionFailure("A resolved SQL element requires a scalar or composite type")
        }
    }

    private enum PairVisit {
        case nodes(QueryTypeStorage, Int, QueryTypeStorage, Int)
        case columns(QueryTypeStorage, Range<Int>, QueryTypeStorage, Range<Int>, Int)
    }

    static func areEqual(_ a: QueryTypeStorage, _ left: Int,
                         _ b: QueryTypeStorage, _ right: Int) -> Bool {
        var work: [PairVisit] = [.nodes(a, left, b, right)]
        while let visit = work.popLast() {
            switch visit {
            case .nodes(let a, let i, let b, let j):
                switch (a.records[i].kind, b.records[j].kind) {
                case (.array(let x), .array(let y)): work.append(.nodes(a, x, b, y))
                case (.composite(let x), .composite(let y)):
                    guard x.count == y.count else { return false }
                    if !x.isEmpty { work.append(.columns(a, x, b, y, 0)) }
                default:
                    guard a.records[i].kind == b.records[j].kind else { return false }
                }
            case .columns(let a, let x, let b, let y, let offset):
                let left = a.columns[x.lowerBound + offset]
                let right = b.columns[y.lowerBound + offset]
                guard left.number == right.number, left.isNullable == right.isNullable,
                      left.name.utf8.elementsEqual(right.name.utf8) else { return false }
                if offset + 1 < x.count { work.append(.columns(a, x, b, y, offset + 1)) }
                work.append(.nodes(a, left.type, b, right.type))
            }
        }
        return true
    }

    private enum HashVisit {
        case node(Int)
        case columns(Range<Int>, Int)
    }

    func hash(_ index: Int, into hasher: inout Hasher) {
        var work: [HashVisit] = [.node(index)]
        while let visit = work.popLast() {
            switch visit {
            case .node(let id):
                switch records[id].kind {
                case .array(let child): hasher.combine(0); work.append(.node(child))
                case .composite(let range):
                    hasher.combine(1); hasher.combine(range.count)
                    if !range.isEmpty { work.append(.columns(range, 0)) }
                default: hasher.combine(2); hasher.combine(records[id].kind)
                }
            case .columns(let range, let offset):
                let column = columns[range.lowerBound + offset]
                hasher.combine(column.number); hasher.combine(column.isNullable)
                hasher.combine(column.name.utf8.count)
                for byte in column.name.utf8 { hasher.combine(byte) }
                if offset + 1 < range.count { work.append(.columns(range, offset + 1)) }
                work.append(.node(column.type))
            }
        }
    }
}
