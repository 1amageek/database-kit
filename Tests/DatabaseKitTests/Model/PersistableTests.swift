import DatabaseTypes
import Testing
@testable import DatabaseKit

@Suite("Persistable Protocol Tests")
struct PersistableProtocolTests {

    // Test struct implementing Persistable manually
    struct TestUser: Persistable, Sendable {
        typealias ID = String

        var id: String = "fixture-id"

        static var persistableType: String { "TestUser" }
        static var allFields: [String] { ["id", "email", "name"] }
        static var indexDescriptors: [IndexDescriptor] { [] }

        static func fieldNumber(for fieldName: String) -> Int? {
            switch fieldName {
            case "id": return 1
            case "email": return 2
            case "name": return 3
            default: return nil
            }
        }

        static func enumMetadata(for fieldName: String) -> EnumMetadata? {
            return nil
        }

        var email: String
        var name: String

        func encodePersistedFields<Output: PersistedFieldOutput>(
            to output: inout Output
        ) throws(PersistableEncodingFailure<Output.Failure>) {
            try output.write(
                FieldIdentity(name: "id", number: 1),
                value: id,
                entity: Self.persistableType
            )
            try output.write(
                FieldIdentity(name: "email", number: 2),
                value: email,
                entity: Self.persistableType
            )
            try output.write(
                FieldIdentity(name: "name", number: 3),
                value: name,
                entity: Self.persistableType
            )
        }
    }

    @Test("Model modelName")
    func testModelName() {
        #expect(TestUser.persistableType == "TestUser")
    }

    @Test("Model allFields includes id")
    func testAllFieldsIncludesId() {
        #expect(TestUser.allFields.contains("id"))
        #expect(TestUser.allFields == ["id", "email", "name"])
    }

    @Test("Model fieldNumber")
    func testFieldNumber() {
        #expect(TestUser.fieldNumber(for: "id") == 1)
        #expect(TestUser.fieldNumber(for: "email") == 2)
        #expect(TestUser.fieldNumber(for: "name") == 3)
        #expect(TestUser.fieldNumber(for: "unknown") == nil)
    }

    @Test("Model owns its id generation policy")
    func modelOwnsIDGenerationPolicy() {
        let user = TestUser(email: "test@example.com", name: "Alice")

        #expect(user.id == "fixture-id")
    }

    @Test("Model Sendable conformance")
    func testSendable() {
        // If this compiles, Sendable conformance is working
        let user = TestUser(email: "test@example.com", name: "Alice")

        Task {
            let _ = user  // Can be captured in async context
        }

        #expect(!user.id.isEmpty)
    }

    @Test("Model canonical field lookup")
    func testCanonicalFieldLookup() throws {
        let user = TestUser(email: "test@example.com", name: "Alice")

        #expect(
            try user.persistedFieldValue(
                for: FieldIdentity(name: "email", number: 2)
            ) == .string("test@example.com")
        )
        #expect(
            try user.persistedFieldValue(
                for: FieldIdentity(name: "name", number: 3)
            ) == .string("Alice")
        )
        #expect(
            try user.persistedFieldValue(
                for: FieldIdentity(name: "id", number: 1)
            ) == .string(user.id)
        )
        #expect(
            try user.persistedFieldValue(
                for: FieldIdentity(name: "nonexistent", number: 100)
            ) == nil
        )
    }
}
