extension PersistableIdentifierValue: Hashable {
    public static func == (
        left: PersistableIdentifierValue,
        right: PersistableIdentifierValue
    ) -> Bool {
        switch (left, right) {
        case (.bool(let left), .bool(let right)):
            return left == right
        case (.int64(let left), .int64(let right)):
            return left == right
        case (.uint64(let left), .uint64(let right)):
            return left == right
        case (.string(let left), .string(let right)):
            return DatabaseStringIdentity.equal(left, right)
        case (.bytes(let left), .bytes(let right)):
            return left == right
        case (.uuid(let left), .uuid(let right)):
            return left == right
        case (.composite(let left), .composite(let right)):
            return left == right
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .bool(let value):
            hasher.combine(0 as UInt8)
            hasher.combine(value)
        case .int64(let value):
            hasher.combine(1 as UInt8)
            hasher.combine(value)
        case .uint64(let value):
            hasher.combine(2 as UInt8)
            hasher.combine(value)
        case .string(let value):
            hasher.combine(3 as UInt8)
            DatabaseStringIdentity.hash(value, into: &hasher)
        case .bytes(let value):
            hasher.combine(4 as UInt8)
            hasher.combine(value)
        case .uuid(let value):
            hasher.combine(5 as UInt8)
            hasher.combine(value)
        case .composite(let values):
            hasher.combine(6 as UInt8)
            hasher.combine(values)
        }
    }
}
