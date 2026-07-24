import DatabaseTypes
public protocol DatabaseReadCommandDescriptor: DatabaseCommandDescriptor {}

extension DatabaseReadCommandDescriptor {
    public static var access: DatabaseCommandAccess { .readOnly }
}
