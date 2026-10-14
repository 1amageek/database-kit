import DatabaseTypes

extension QueryArray: FieldValueEncodable, FieldValueDecodable, QueryLiteralConvertible {
    public static var fieldSchemaType: FieldSchemaType { .object }
    public static var queryType: QueryColumnType? { .sql(.array(Element.queryDataType)) }

    public func encodeFieldValue() throws(PersistableEncodingError) -> FieldValue {
        let value = QueryValue.array(arrayValue)
        let type = QueryColumnType.sql(.array(Element.queryDataType))
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
        let type = QueryColumnType.sql(.array(Element.queryDataType))
        do throws(QueryValueError) {
            let limits = try QueryFieldStorageAdapter.inferredLimits(for: value, type: type)
            let decoded = try QueryFieldStorageAdapter.decode(value, type: type, limits: limits)
            guard case .array(let array) = decoded else {
                throw QueryValueError.incompatibleType
            }
            return try Self(arrayValue: array, limits: limits)
        } catch let cause {
            throw .invalidQueryValue(field: field, cause: cause)
        }
    }

    public var queryLiteral: Literal {
        .queryValue(.array(arrayValue), type: .sql(.array(Element.queryDataType)))
    }
}
