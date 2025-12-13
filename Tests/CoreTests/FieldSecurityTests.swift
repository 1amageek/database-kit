// FieldSecurityTests.swift
// Core - Tests for field-level security types

import Testing
import Foundation
@testable import Core

// MARK: - Test Auth Context

private struct TestAuth: AuthContext {
    let userID: String
    var roles: Set<String>

    init(userID: String, roles: Set<String> = []) {
        self.userID = userID
        self.roles = roles
    }
}

// MARK: - FieldAccessLevel Tests

@Suite("FieldAccessLevel")
struct FieldAccessLevelTests {

    @Test("Public access allows everyone")
    func publicAccessAllowsEveryone() {
        let level = FieldAccessLevel.public

        // Unauthenticated
        #expect(level.evaluate(auth: nil) == true)

        // Authenticated without roles
        #expect(level.evaluate(auth: TestAuth(userID: "user1")) == true)

        // Authenticated with roles
        #expect(level.evaluate(auth: TestAuth(userID: "user1", roles: ["admin"])) == true)
    }

    @Test("Authenticated access requires auth")
    func authenticatedAccessRequiresAuth() {
        let level = FieldAccessLevel.authenticated

        // Unauthenticated
        #expect(level.evaluate(auth: nil) == false)

        // Authenticated
        #expect(level.evaluate(auth: TestAuth(userID: "user1")) == true)
    }

    @Test("Role-based access checks roles")
    func roleBasedAccessChecksRoles() {
        let level = FieldAccessLevel.roles(["hr", "manager"])

        // Unauthenticated
        #expect(level.evaluate(auth: nil) == false)

        // Authenticated without required roles
        #expect(level.evaluate(auth: TestAuth(userID: "user1", roles: ["employee"])) == false)

        // Authenticated with one required role
        #expect(level.evaluate(auth: TestAuth(userID: "user1", roles: ["hr"])) == true)
        #expect(level.evaluate(auth: TestAuth(userID: "user1", roles: ["manager"])) == true)

        // Authenticated with multiple roles including required
        #expect(level.evaluate(auth: TestAuth(userID: "user1", roles: ["employee", "hr"])) == true)
    }

    @Test("Custom access uses predicate")
    func customAccessUsesPredicate() {
        let level = FieldAccessLevel.custom { auth in
            auth.userID.hasPrefix("admin_")
        }

        // Unauthenticated
        #expect(level.evaluate(auth: nil) == false)

        // Not matching predicate
        #expect(level.evaluate(auth: TestAuth(userID: "user1")) == false)

        // Matching predicate
        #expect(level.evaluate(auth: TestAuth(userID: "admin_1")) == true)
    }

    @Test("FieldAccessLevel equality")
    func fieldAccessLevelEquality() {
        #expect(FieldAccessLevel.public == FieldAccessLevel.public)
        #expect(FieldAccessLevel.authenticated == FieldAccessLevel.authenticated)
        #expect(FieldAccessLevel.roles(["a", "b"]) == FieldAccessLevel.roles(["a", "b"]))
        #expect(FieldAccessLevel.roles(["a"]) != FieldAccessLevel.roles(["b"]))

        // Custom closures cannot be compared
        let custom1 = FieldAccessLevel.custom { _ in true }
        let custom2 = FieldAccessLevel.custom { _ in true }
        #expect(custom1 != custom2)
    }

    @Test("FieldAccessLevel description")
    func fieldAccessLevelDescription() {
        #expect(FieldAccessLevel.public.description == ".public")
        #expect(FieldAccessLevel.authenticated.description == ".authenticated")
        #expect(FieldAccessLevel.roles(["admin"]).description.contains("admin"))
        #expect(FieldAccessLevel.custom { _ in true }.description == ".custom(...)")
    }
}

// MARK: - Restricted Property Wrapper Tests

@Suite("Restricted Property Wrapper")
struct RestrictedPropertyWrapperTests {

    @Test("Restricted wraps value correctly")
    func restrictedWrapsValue() {
        var restricted = Restricted(wrappedValue: 100.0, read: .roles(["hr"]), write: .roles(["admin"]))

        #expect(restricted.wrappedValue == 100.0)
        #expect(restricted.readAccess == .roles(["hr"]))
        #expect(restricted.writeAccess == .roles(["admin"]))

        // Can modify wrapped value
        restricted.wrappedValue = 200.0
        #expect(restricted.wrappedValue == 200.0)
    }

    @Test("Restricted with default access levels")
    func restrictedWithDefaultAccessLevels() {
        let restricted = Restricted(wrappedValue: "test")

        #expect(restricted.wrappedValue == "test")
        #expect(restricted.readAccess == .public)
        #expect(restricted.writeAccess == .public)
    }

    @Test("Restricted conforms to RestrictedProtocol")
    func restrictedConformsToProtocol() {
        let restricted: any RestrictedProtocol = Restricted(
            wrappedValue: "secret",
            read: .authenticated,
            write: .roles(["admin"])
        )

        #expect(restricted.readAccess == .authenticated)
        #expect(restricted.writeAccess == .roles(["admin"]))
        #expect(restricted.anyValue as? String == "secret")
        #expect(Restricted<String>.valueType is String.Type)
    }

    @Test("Restricted Codable encodes only value")
    func restrictedCodableEncodesOnlyValue() throws {
        let restricted = Restricted(
            wrappedValue: 42,
            read: .roles(["hr"]),
            write: .roles(["admin"])
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(restricted)
        let json = String(data: data, encoding: .utf8)

        // Should encode just the value, not access levels
        #expect(json == "42")

        // Decode back
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Restricted<Int>.self, from: data)
        #expect(decoded.wrappedValue == 42)
        // Access levels are not encoded, so they default to .public
        #expect(decoded.readAccess == .public)
        #expect(decoded.writeAccess == .public)
    }

    @Test("Restricted Equatable")
    func restrictedEquatable() {
        let r1 = Restricted(wrappedValue: 100, read: .authenticated, write: .public)
        let r2 = Restricted(wrappedValue: 100, read: .authenticated, write: .public)
        let r3 = Restricted(wrappedValue: 200, read: .authenticated, write: .public)
        let r4 = Restricted(wrappedValue: 100, read: .public, write: .public)

        #expect(r1 == r2)
        #expect(r1 != r3) // different value
        #expect(r1 != r4) // different access level
    }

    @Test("Restricted Hashable")
    func restrictedHashable() {
        let r1 = Restricted(wrappedValue: "test", read: .authenticated)
        let r2 = Restricted(wrappedValue: "test", read: .public)

        // Same value should have same hash (access levels not included in hash)
        #expect(r1.hashValue == r2.hashValue)

        // Can be used in Set
        var set: Set<Restricted<String>> = []
        set.insert(r1)
        #expect(set.count == 1)
    }

    @Test("Restricted projected value")
    func restrictedProjectedValue() {
        var restricted = Restricted(wrappedValue: "value", read: .authenticated)

        // Projected value provides access to the wrapper itself
        let projected = restricted.projectedValue
        #expect(projected.readAccess == .authenticated)

        // Can modify via projected value
        restricted.projectedValue = Restricted(wrappedValue: "new", read: .public)
        #expect(restricted.wrappedValue == "new")
        #expect(restricted.readAccess == .public)
    }
}
