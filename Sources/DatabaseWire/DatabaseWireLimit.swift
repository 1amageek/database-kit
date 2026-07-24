import DatabaseTypes
public enum DatabaseWireLimit: Sendable, Hashable {
    case frameBytes
    case stringBytes
    case byteStringBytes
    case collectionElements
    case nestingDepth
    case objects
}
