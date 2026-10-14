public enum QueryValueError: Error, Sendable, Equatable {
    case invalidNumericDisplayScale(Int32)
    case numericOutOfRange
    case invalidJSON(offset: UInt64, reason: String)
    case invalidUTF8(offset: UInt64)
    case nonCanonicalJSONB
    case invalidDimensionCount(Int)
    case invalidDimension(lowerBound: Int32, length: Int32)
    case dimensionProductOverflow
    case elementCountMismatch(expected: UInt64, actual: UInt64)
    case elementTypeMismatch(index: UInt64)
    case incompatibleType
    case invalidColumnNumber(UInt32)
    case invalidPersistenceDescriptor
    case invalidPersistencePayload(reason: String)
    case intervalOutOfRange
    case unknownRetainedByteCount
    case resourceLimit(resource: String, actual: UInt64, maximum: UInt64)
    case arithmeticOverflow
}
