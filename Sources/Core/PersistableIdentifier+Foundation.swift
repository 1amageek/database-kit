import DatabaseTypes
import DatabaseValue
import DatabaseTypesFoundation
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Data: PersistableIdentifier {
    public static var persistableIdentifierType: PersistableIdentifierType { .bytes }

    public var persistableIdentifierValue: ReferenceIdentifier {
        .bytes(ByteString(retaining: self))
    }
}

extension Foundation.UUID: PersistableIdentifier {
    public static var persistableIdentifierType: PersistableIdentifierType { .uuid }

    public var persistableIdentifierValue: ReferenceIdentifier {
        .uuid(DatabaseTypes.UUID(self))
    }
}
