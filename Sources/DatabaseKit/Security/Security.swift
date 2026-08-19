/// Database authorization vocabulary.
public enum Security {
    public struct Access: OptionSet, Sendable, Hashable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let read = Self(rawValue: 1 << 0)
        public static let write = Self(rawValue: 1 << 1)
        public static let administer = Self(rawValue: 1 << 2)
        public static let all: Self = [.read, .write, .administer]

        public var containsOnlyKnownPermissions: Bool {
            rawValue & ~Self.all.rawValue == 0
        }
    }

    #if DATABASE_KIT_MULTI_BASE
    public enum Resource: Sendable, Hashable {
        case database
        case base(Base.ID)
    }

    public enum Subject: Sendable, Hashable {
        case principal(String)
        case principalRole(String)
    }

    public struct Grant: Sendable, Hashable {
        public let subject: Subject
        public let resource: Resource
        public let access: Access

        public init(
            subject: Subject,
            resource: Resource,
            access: Access
        ) {
            self.subject = subject
            self.resource = resource
            self.access = access
        }
    }
    #endif
}
