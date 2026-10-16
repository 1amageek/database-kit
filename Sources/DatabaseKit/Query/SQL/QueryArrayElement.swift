import DatabaseTypes

public protocol QueryArrayElement: Sendable {
    static var queryDataType: DataType { get }
    var queryValue: QueryValue { get throws(QueryValueError) }
    static func decodeQueryValue(_ value: QueryValue) throws(QueryValueError) -> Self
}

public extension QueryArrayElement where Self: FieldValueEncodable & FieldValueDecodable {
    var queryValue: QueryValue {
        get throws(QueryValueError) {
            do { return .primitive(try encodeFieldValue()) }
            catch { throw .incompatibleType }
        }
    }

    static func decodeQueryValue(_ value: QueryValue) throws(QueryValueError) -> Self {
        guard case .primitive(let value) = value else { throw .incompatibleType }
        do { return try decodeFieldValue(value, field: "array element") }
        catch { throw .incompatibleType }
    }
}

extension Bool: QueryArrayElement { public static var queryDataType: DataType { .boolean } }
extension Int16: QueryArrayElement { public static var queryDataType: DataType { .smallint } }
extension Int32: QueryArrayElement { public static var queryDataType: DataType { .integer } }
extension Int64: QueryArrayElement { public static var queryDataType: DataType { .bigint } }
extension Float: QueryArrayElement { public static var queryDataType: DataType { .real } }
extension Double: QueryArrayElement { public static var queryDataType: DataType { .doublePrecision } }
extension String: QueryArrayElement { public static var queryDataType: DataType { .text } }
extension ByteString: QueryArrayElement { public static var queryDataType: DataType { .blob } }
extension DatabaseTypes.UUID: QueryArrayElement { public static var queryDataType: DataType { .uuid } }
extension CivilDate: QueryArrayElement { public static var queryDataType: DataType { .date } }
extension CivilTime: QueryArrayElement { public static var queryDataType: DataType { .time(withTimeZone: false) } }
extension CivilDateTime: QueryArrayElement { public static var queryDataType: DataType { .timestamp(withTimeZone: false) } }
extension Timestamp: QueryArrayElement { public static var queryDataType: DataType { .timestamp(withTimeZone: true) } }

extension QueryNumericValue: QueryArrayElement {
    public static var queryDataType: DataType { .decimal(precision: nil, scale: nil) }
    public var queryValue: QueryValue { .numeric(self) }
    public static func decodeQueryValue(_ value: QueryValue) throws(QueryValueError) -> Self {
        guard case .numeric(let value) = value else { throw .incompatibleType }
        return value
    }
}

extension QueryJSONValue: QueryArrayElement {
    public static var queryDataType: DataType { .json }
    public var queryValue: QueryValue { .json(self) }
    public static func decodeQueryValue(_ value: QueryValue) throws(QueryValueError) -> Self {
        guard case .json(let value) = value else { throw .incompatibleType }
        return value
    }
}

extension QueryJSONBValue: QueryArrayElement {
    public static var queryDataType: DataType { .jsonb }
    public var queryValue: QueryValue { .jsonb(self) }
    public static func decodeQueryValue(_ value: QueryValue) throws(QueryValueError) -> Self {
        guard case .jsonb(let value) = value else { throw .incompatibleType }
        return value
    }
}

extension QueryIntervalValue: QueryArrayElement {
    public static var queryDataType: DataType { .interval() }
    public var queryValue: QueryValue { .interval(self) }
    public static func decodeQueryValue(_ value: QueryValue) throws(QueryValueError) -> Self {
        guard case .interval(let value) = value else { throw .incompatibleType }
        return value
    }
}


extension QueryTimeValue: QueryArrayElement {
    public static var queryDataType: DataType { .time(withTimeZone: false) }
    public var queryValue: QueryValue { .time(self) }
    public static func decodeQueryValue(_ value: QueryValue) throws(QueryValueError) -> Self {
        guard case .time(let value) = value else { throw .incompatibleType }
        return value
    }
}

extension QueryTimeWithTimeZoneValue: QueryArrayElement {
    public static var queryDataType: DataType { .time(withTimeZone: true) }
    public var queryValue: QueryValue { .timeWithTimeZone(self) }
    public static func decodeQueryValue(_ value: QueryValue) throws(QueryValueError) -> Self {
        guard case .timeWithTimeZone(let value) = value else { throw .incompatibleType }
        return value
    }
}
