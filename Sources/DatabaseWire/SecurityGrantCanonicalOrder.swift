import DatabaseKit

enum SecurityGrantCanonicalOrder {
    static func validate(
        _ grants: [Security.Grant]
    ) throws(DatabaseWireError) {
        for (previous, current) in zip(grants, grants.dropFirst()) {
            guard precedes(previous, current) else {
                throw .nonCanonicalGrantSet
            }
        }
    }

    static func precedes(
        _ lhs: Security.Grant,
        _ rhs: Security.Grant
    ) -> Bool {
        let lhsSubject = subjectKey(lhs.subject)
        let rhsSubject = subjectKey(rhs.subject)
        if lhsSubject != rhsSubject {
            return lhsSubject < rhsSubject
        }
        let lhsResource = resourceKey(lhs.resource)
        let rhsResource = resourceKey(rhs.resource)
        if lhsResource != rhsResource {
            return lhsResource < rhsResource
        }
        return lhs.access.rawValue < rhs.access.rawValue
    }

    private static func subjectKey(
        _ subject: Security.Subject
    ) -> SubjectKey {
        switch subject {
        case .principal(let identifier):
            return SubjectKey(tag: 0, value: identifier)
        case .principalRole(let role):
            return SubjectKey(tag: 1, value: role)
        }
    }

    private static func resourceKey(
        _ resource: Security.Resource
    ) -> ResourceKey {
        switch resource {
        case .database:
            return ResourceKey(tag: 0, value: "")
        case .base(let baseID):
            return ResourceKey(tag: 1, value: baseID.value)
        }
    }

    private struct SubjectKey: Comparable {
        let tag: UInt8
        let value: String

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.tag != rhs.tag ? lhs.tag < rhs.tag : lhs.value < rhs.value
        }
    }

    private struct ResourceKey: Comparable {
        let tag: UInt8
        let value: String

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.tag != rhs.tag ? lhs.tag < rhs.tag : lhs.value < rhs.value
        }
    }
}
