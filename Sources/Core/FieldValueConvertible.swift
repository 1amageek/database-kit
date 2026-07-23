import DatabaseValue

/// A value that can be represented by the canonical database field model.
public protocol FieldValueConvertible: Sendable {
    func toFieldValue() -> FieldValue
}

extension Bool: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .bool(self) }
}

extension Int: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .int64(Int64(self)) }
}

extension Int8: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .int64(Int64(self)) }
}

extension Int16: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .int64(Int64(self)) }
}

extension Int32: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .int64(Int64(self)) }
}

extension Int64: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .int64(self) }
}

extension UInt: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uint64(UInt64(self)) }
}

extension UInt8: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uint64(UInt64(self)) }
}

extension UInt16: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uint64(UInt64(self)) }
}

extension UInt32: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uint64(UInt64(self)) }
}

extension UInt64: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uint64(self) }
}

extension Float: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .double(Double(self)) }
}

extension Double: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .double(self) }
}

extension String: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .string(self) }
}

extension DatabaseBytes: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .bytes(self) }
}

extension DatabaseDate: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .date(self) }
}

extension DatabaseTimestamp: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .timestamp(self) }
}

extension DatabaseUUID: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uuid(self) }
}

extension DatabaseRDFTerm: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .rdfTerm(self) }
}

extension Array: FieldValueConvertible where Element: FieldValueConvertible {
    public func toFieldValue() -> FieldValue {
        .array(map { $0.toFieldValue() })
    }
}

extension FieldValue: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { self }
}
