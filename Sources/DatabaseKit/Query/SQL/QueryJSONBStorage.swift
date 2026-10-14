/// One immutable owner. Records contain indices, never recursively owned nodes.
final class QueryJSONBStorage: Sendable {
    enum Record: Sendable {
        case null
        case bool(Bool)
        case string(String)
        case number(QueryNumericValue)
        case array(Range<Int>)
        case object(Range<Int>)
    }

    struct Member: Sendable {
        let key: String
        let value: Int
    }

    let records: [Record]
    let elements: [Int]
    let members: [Member]
    let footprint: QueryJSONBStorageFootprint

    init(records: [Record], elements: [Int], members: [Member],
         footprint: QueryJSONBStorageFootprint) {
        self.records = records
        self.elements = elements
        self.members = members
        self.footprint = footprint
    }

    func node(at index: Int) -> QueryJSONBNode {
        switch records[index] {
        case .null: return .null
        case .bool(let value): return .bool(value)
        case .string(let value): return .string(value)
        case .number(let value): return .number(value)
        case .array(let range): return .array(QueryJSONBElements(storage: self, range: range))
        case .object(let range): return .object(QueryJSONBMembers(storage: self, range: range))
        }
    }
}
