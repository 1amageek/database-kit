extension Bool: PersistableIdentifier {
    public static var persistableIdentifierType: PersistableIdentifierType { .bool }
    public var persistableIdentifierValue: PersistableIdentifierValue { .bool(self) }
}

extension Int8: PersistableIdentifier {
    public static var persistableIdentifierType: PersistableIdentifierType { .int8 }
    public var persistableIdentifierValue: PersistableIdentifierValue { .int8(self) }
}

extension Int16: PersistableIdentifier {
    public static var persistableIdentifierType: PersistableIdentifierType { .int16 }
    public var persistableIdentifierValue: PersistableIdentifierValue { .int16(self) }
}

extension Int32: PersistableIdentifier {
    public static var persistableIdentifierType: PersistableIdentifierType { .int32 }
    public var persistableIdentifierValue: PersistableIdentifierValue { .int32(self) }
}

extension Int64: PersistableIdentifier {
    public static var persistableIdentifierType: PersistableIdentifierType { .int64 }
    public var persistableIdentifierValue: PersistableIdentifierValue { .int64(self) }
}

extension UInt8: PersistableIdentifier {
    public static var persistableIdentifierType: PersistableIdentifierType { .uint8 }
    public var persistableIdentifierValue: PersistableIdentifierValue { .uint8(self) }
}

extension UInt16: PersistableIdentifier {
    public static var persistableIdentifierType: PersistableIdentifierType { .uint16 }
    public var persistableIdentifierValue: PersistableIdentifierValue { .uint16(self) }
}

extension UInt32: PersistableIdentifier {
    public static var persistableIdentifierType: PersistableIdentifierType { .uint32 }
    public var persistableIdentifierValue: PersistableIdentifierValue { .uint32(self) }
}

extension UInt64: PersistableIdentifier {
    public static var persistableIdentifierType: PersistableIdentifierType { .uint64 }
    public var persistableIdentifierValue: PersistableIdentifierValue { .uint64(self) }
}

extension String: PersistableIdentifier {
    public static var persistableIdentifierType: PersistableIdentifierType { .string }
    public var persistableIdentifierValue: PersistableIdentifierValue { .string(self) }
}

extension DatabaseBytes: PersistableIdentifier {
    public static var persistableIdentifierType: PersistableIdentifierType { .bytes }
    public var persistableIdentifierValue: PersistableIdentifierValue { .bytes(self) }
}

extension DatabaseUUID: PersistableIdentifier {
    public static var persistableIdentifierType: PersistableIdentifierType { .uuid }
    public var persistableIdentifierValue: PersistableIdentifierValue { .uuid(self) }
}

extension Array: PersistableIdentifier where Element == UInt8 {
    public static var persistableIdentifierType: PersistableIdentifierType { .bytes }

    public var persistableIdentifierValue: PersistableIdentifierValue {
        .bytes(DatabaseBytes(self))
    }
}
