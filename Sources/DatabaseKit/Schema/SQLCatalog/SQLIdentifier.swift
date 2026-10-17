/// Exact SQL identifier identity without Unicode normalization or byte copying.
struct SQLIdentifier: Hashable {
    let value: String

    static func validate(_ value: String) throws(SQLCatalogError) {
        guard !value.isEmpty else { throw .emptyIdentifier }
        guard !value.utf8.contains(0) else { throw .nulInIdentifier }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value.utf8.elementsEqual(rhs.value.utf8)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value.utf8.count)
        for byte in value.utf8 { hasher.combine(byte) }
    }

    static func equal(_ lhs: [String]?, _ rhs: [String]?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (.some(let left), .some(let right)):
            guard left.count == right.count else { return false }
            for index in left.indices {
                guard SQLIdentifier(value: left[index]) == SQLIdentifier(value: right[index]) else {
                    return false
                }
            }
            return true
        default:
            return false
        }
    }
}
