public struct SchemaVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let major: UInt32
    public let minor: UInt32
    public let patch: UInt32

    public init(_ major: UInt32, _ minor: UInt32, _ patch: UInt32) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (
        lhs: SchemaVersion,
        rhs: SchemaVersion
    ) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }
}
