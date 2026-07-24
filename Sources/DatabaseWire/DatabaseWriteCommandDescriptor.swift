import DatabaseTypes
public protocol DatabaseWriteCommandDescriptor: DatabaseCommandDescriptor {}

extension DatabaseWriteCommandDescriptor {
    public static var access: DatabaseCommandAccess { .readWrite }
}
