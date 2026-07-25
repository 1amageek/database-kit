import DatabaseTypes
// FieldSecurityTests.swift
// Core - Tests for field-level security types

import Testing
import Foundation
@testable import DatabaseKit

@Persistable
private struct RestrictedEmployee {
    var id: String

    @Restricted(
        read: .roles(["hr", "manager"]),
        write: .roles(["hr"])
    )
    var salary: Double = 0
}

@Persistable
private struct SecuredDocument: SecurityPolicy {
    var id: String
    var ownerIdentifier: String

    static func permitsRead(
        of resource: borrowing SecuredDocument,
        in context: borrowing AuthorizationContext
    ) -> Bool {
        resource.ownerIdentifier == context.principal?.identifier
    }
}

private func authenticated(
    _ identifier: String,
    roles: Set<String> = []
) -> AuthorizationContext {
    .authenticated(
        Principal(
            identifier: identifier,
            roles: roles
        )
    )
}

// MARK: - FieldAccessLevel Tests

@Suite("FieldAccessLevel")
struct FieldAccessLevelTests {

    @Test("Public access allows everyone")
    func publicAccessAllowsEveryone() {
        let level = FieldAccessLevel.public

        // Unauthenticated
        #expect(level.allows(.anonymous))

        // Authenticated without roles
        #expect(level.allows(authenticated("user1")))

        // Authenticated with roles
        #expect(level.allows(authenticated("user1", roles: ["admin"])))
    }

    @Test("Authenticated access requires auth")
    func authenticatedAccessRequiresAuth() {
        let level = FieldAccessLevel.authenticated

        // Unauthenticated
        #expect(!level.allows(.anonymous))

        // Authenticated
        #expect(level.allows(authenticated("user1")))
    }

    @Test("Role-based access checks roles")
    func roleBasedAccessChecksRoles() {
        let level = FieldAccessLevel.roles(["hr", "manager"])

        // Unauthenticated
        #expect(!level.allows(.anonymous))

        // Authenticated without required roles
        #expect(!level.allows(authenticated("user1", roles: ["employee"])))

        // Authenticated with one required role
        #expect(level.allows(authenticated("user1", roles: ["hr"])))
        #expect(level.allows(authenticated("user1", roles: ["manager"])))

        // Authenticated with multiple roles including required
        #expect(level.allows(authenticated("user1", roles: ["employee", "hr"])))
    }

    @Test("FieldAccessLevel equality")
    func fieldAccessLevelEquality() {
        #expect(FieldAccessLevel.public == FieldAccessLevel.public)
        #expect(FieldAccessLevel.authenticated == FieldAccessLevel.authenticated)
        #expect(FieldAccessLevel.roles(["a", "b"]) == FieldAccessLevel.roles(["a", "b"]))
        #expect(FieldAccessLevel.roles(["a"]) != FieldAccessLevel.roles(["b"]))

    }

    @Test("FieldAccessLevel description")
    func fieldAccessLevelDescription() {
        #expect(FieldAccessLevel.public.description == ".public")
        #expect(FieldAccessLevel.authenticated.description == ".authenticated")
        #expect(FieldAccessLevel.roles(["admin"]).description.contains("admin"))
    }

    @Test("Typed security policy receives a concrete authorization context")
    func typedSecurityPolicy() {
        let document = SecuredDocument(
            id: "document-1",
            ownerIdentifier: "owner-1"
        )

        #expect(
            SecuredDocument.permitsRead(
                of: document,
                in: authenticated("owner-1")
            )
        )
        #expect(
            !SecuredDocument.permitsRead(
                of: document,
                in: .anonymous
            )
        )
    }
}

// MARK: - Restricted Property Wrapper Tests

@Suite("Restricted Property Wrapper")
struct RestrictedPropertyWrapperTests {

    @Test("Restricted wraps value correctly")
    func restrictedWrapsValue() {
        var restricted = Restricted(wrappedValue: 100.0, read: .roles(["hr"]), write: .roles(["admin"]))

        #expect(restricted.wrappedValue == 100.0)

        // Can modify wrapped value
        restricted.wrappedValue = 200.0
        #expect(restricted.wrappedValue == 200.0)
    }

    @Test("Restricted with default access levels")
    func restrictedWithDefaultAccessLevels() {
        let restricted = Restricted(wrappedValue: "test")

        #expect(restricted.wrappedValue == "test")
    }

    @Test("Restricted Equatable")
    func restrictedEquatable() {
        let r1 = Restricted(wrappedValue: 100, read: .authenticated, write: .public)
        let r2 = Restricted(wrappedValue: 100, read: .authenticated, write: .public)
        let r3 = Restricted(wrappedValue: 200, read: .authenticated, write: .public)
        let r4 = Restricted(wrappedValue: 100, read: .public, write: .public)

        #expect(r1 == r2)
        #expect(r1 != r3) // different value
        #expect(r1 == r4) // authorization is static schema data
    }

    @Test("Restricted Hashable")
    func restrictedHashable() {
        let r1 = Restricted(wrappedValue: "test", read: .authenticated)
        let r2 = Restricted(wrappedValue: "test", read: .public)

        #expect(r1.hashValue == r2.hashValue)

        let set: Set<Restricted<String>> = [r1, r2]
        #expect(set.count == 1)
    }

    @Test("@Restricted compiles authorization into schema")
    func restrictedCompilesStaticRule() throws {
        let salary = RestrictedEmployee.fields.salary.identity
        let expected = FieldAccessRule(
            field: salary,
            read: .roles(["hr", "manager"]),
            write: .roles(["hr"])
        )

        #expect(RestrictedEmployee.fieldAccessRules == [expected])
        #expect(try RestrictedEmployee.schemaEntity.fieldAccessRules == [expected])
    }
}
