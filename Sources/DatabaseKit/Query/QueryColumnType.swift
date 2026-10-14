public enum QueryColumnType: Sendable, Hashable {
    case sql(DataType)
    case primitive(FieldSchemaType, isArray: Bool = false)
}
