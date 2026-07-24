extension PersistableIdentifierValue: Hashable {
    public static func == (
        left: PersistableIdentifierValue,
        right: PersistableIdentifierValue
    ) -> Bool {
        switch (left, right) {
        case (.bool(let left), .bool(let right)):
            return left == right
        case (.int8(let left), .int8(let right)):
            return left == right
        case (.int16(let left), .int16(let right)):
            return left == right
        case (.int32(let left), .int32(let right)):
            return left == right
        case (.int64(let left), .int64(let right)):
            return left == right
        case (.uint8(let left), .uint8(let right)):
            return left == right
        case (.uint16(let left), .uint16(let right)):
            return left == right
        case (.uint32(let left), .uint32(let right)):
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
        case .int8(let value):
            hasher.combine(1 as UInt8)
            hasher.combine(value)
        case .int16(let value):
            hasher.combine(2 as UInt8)
            hasher.combine(value)
        case .int32(let value):
            hasher.combine(3 as UInt8)
            hasher.combine(value)
        case .int64(let value):
            hasher.combine(4 as UInt8)
            hasher.combine(value)
        case .uint8(let value):
            hasher.combine(5 as UInt8)
            hasher.combine(value)
        case .uint16(let value):
            hasher.combine(6 as UInt8)
            hasher.combine(value)
        case .uint32(let value):
            hasher.combine(7 as UInt8)
            hasher.combine(value)
        case .uint64(let value):
            hasher.combine(8 as UInt8)
            hasher.combine(value)
        case .string(let value):
            hasher.combine(9 as UInt8)
            DatabaseStringIdentity.hash(value, into: &hasher)
        case .bytes(let value):
            hasher.combine(10 as UInt8)
            hasher.combine(value)
        case .uuid(let value):
            hasher.combine(11 as UInt8)
            hasher.combine(value)
        case .composite(let values):
            hasher.combine(12 as UInt8)
            hasher.combine(values)
        }
    }
}
