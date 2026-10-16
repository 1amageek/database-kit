import DatabaseTypes

extension QueryTimeValue: FieldValueEncodable, FieldValueDecodable, QueryLiteralConvertible {
    public static var fieldSchemaType: FieldSchemaType { .time }
    public static var queryType: QueryColumnType? { .sql(.time(withTimeZone: false)) }

    public func encodeFieldValue() throws(PersistableEncodingError) -> FieldValue {
        let value = QueryValue.time(self)
        let type = QueryColumnType.sql(.time(withTimeZone: false))
        do throws(QueryValueError) {
            return try QueryFieldStorageAdapter.encode(
                value,
                type: type,
                limits: QueryFieldStorageAdapter.inferredLimits(for: value, type: type)
            )
        } catch let cause {
            throw .invalidQueryValue(cause)
        }
    }

    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> Self {
        let type = QueryColumnType.sql(.time(withTimeZone: false))
        do throws(QueryValueError) {
            let decoded = try QueryFieldStorageAdapter.decode(
                value,
                type: type,
                limits: QueryFieldStorageAdapter.inferredLimits(for: value, type: type)
            )
            guard case .time(let result) = decoded else {
                throw QueryValueError.incompatibleType
            }
            return result
        } catch let cause {
            throw .invalidQueryValue(field: field, cause: cause)
        }
    }

    public var queryLiteral: Literal {
        .queryValue(.time(self), type: .sql(.time(withTimeZone: false)))
    }
}
