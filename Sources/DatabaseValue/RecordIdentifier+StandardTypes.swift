extension Bool: RecordIdentifier {
    public static var recordIdentifierType: RecordIdentifierType { .bool }
    public var recordIdentifierValue: RecordIdentifierValue { .bool(self) }
}

extension Int: RecordIdentifier {
    public static var recordIdentifierType: RecordIdentifierType { .int64 }
    public var recordIdentifierValue: RecordIdentifierValue { .int64(Int64(self)) }
}

extension Int8: RecordIdentifier {
    public static var recordIdentifierType: RecordIdentifierType { .int64 }
    public var recordIdentifierValue: RecordIdentifierValue { .int64(Int64(self)) }
}

extension Int16: RecordIdentifier {
    public static var recordIdentifierType: RecordIdentifierType { .int64 }
    public var recordIdentifierValue: RecordIdentifierValue { .int64(Int64(self)) }
}

extension Int32: RecordIdentifier {
    public static var recordIdentifierType: RecordIdentifierType { .int64 }
    public var recordIdentifierValue: RecordIdentifierValue { .int64(Int64(self)) }
}

extension Int64: RecordIdentifier {
    public static var recordIdentifierType: RecordIdentifierType { .int64 }
    public var recordIdentifierValue: RecordIdentifierValue { .int64(self) }
}

extension UInt: RecordIdentifier {
    public static var recordIdentifierType: RecordIdentifierType { .uint64 }
    public var recordIdentifierValue: RecordIdentifierValue { .uint64(UInt64(self)) }
}

extension UInt8: RecordIdentifier {
    public static var recordIdentifierType: RecordIdentifierType { .uint64 }
    public var recordIdentifierValue: RecordIdentifierValue { .uint64(UInt64(self)) }
}

extension UInt16: RecordIdentifier {
    public static var recordIdentifierType: RecordIdentifierType { .uint64 }
    public var recordIdentifierValue: RecordIdentifierValue { .uint64(UInt64(self)) }
}

extension UInt32: RecordIdentifier {
    public static var recordIdentifierType: RecordIdentifierType { .uint64 }
    public var recordIdentifierValue: RecordIdentifierValue { .uint64(UInt64(self)) }
}

extension UInt64: RecordIdentifier {
    public static var recordIdentifierType: RecordIdentifierType { .uint64 }
    public var recordIdentifierValue: RecordIdentifierValue { .uint64(self) }
}

extension String: RecordIdentifier {
    public static var recordIdentifierType: RecordIdentifierType { .string }
    public var recordIdentifierValue: RecordIdentifierValue { .string(self) }
}

extension DatabaseBytes: RecordIdentifier {
    public static var recordIdentifierType: RecordIdentifierType { .bytes }
    public var recordIdentifierValue: RecordIdentifierValue { .bytes(self) }
}

extension DatabaseUUID: RecordIdentifier {
    public static var recordIdentifierType: RecordIdentifierType { .uuid }
    public var recordIdentifierValue: RecordIdentifierValue { .uuid(self) }
}

extension Array: RecordIdentifier where Element == UInt8 {
    public static var recordIdentifierType: RecordIdentifierType { .bytes }

    public var recordIdentifierValue: RecordIdentifierValue {
        .bytes(DatabaseBytes(self))
    }
}
