/// Errors raised by DatabaseKit wire binary codecs.
public enum DatabaseWireError: Error, Sendable, Equatable {
    case truncated
    case byteCountOverflow
    case invalidBool(UInt8)
    case invalidUTF8
    case trailingBytes
    case unsupportedProtocolVersion(UInt8)
    case unknownOperation(UInt8)
    case unknownResponseStatus(UInt8)
    case unknownResponsePayload(UInt8)
    case unknownFieldType(UInt8)
    case unknownFieldValue(UInt8)
    case unknownIndexKind(UInt8)
    case unknownComparisonOperator(UInt8)
    case unknownPredicate(UInt8)
    case unknownVectorMetric(UInt8)
    case unsupportedPredicatePlan
}
