import DatabaseTypes
import DatabaseValue
import Testing
import Foundation
@testable import Core

/// Tests for @Persistable macro
@Suite("@Persistable Macro Tests")
struct ModelMacroTests {

    /// Test basic @Persistable expansion
    @Test("Basic @Persistable generates id and metadata")
    func basicModel() throws {
        // Verify generated properties
        #expect(BasicUser.persistableType == "BasicUser")
        #expect(BasicUser.allFields.contains("id"))
        #expect(BasicUser.allFields.contains("email"))
        #expect(BasicUser.allFields.contains("name"))
        #expect(try BasicUser.indexDescriptors.isEmpty)

        // Verify auto-generated id
        let user = BasicUser(email: "test@example.com", name: "Alice")
        #expect(!user.id.isEmpty)
    }

    /// Test @Persistable with #Index
    @Test("@Persistable with single Index")
    func modelWithIndex() throws {
        // Verify index descriptors
        let indexes = try IndexedUser.indexDescriptors
        #expect(indexes.count == 1)

        let emailIndex = indexes[0]
        #expect(emailIndex.name == "IndexedUser_email")
        #expect(emailIndex.fieldNames == ["email"])
        #expect(emailIndex.kind.fieldNames == ["email"])
        #expect(emailIndex.kindIdentifier == "scalar")
        #expect(emailIndex.isUnique == true)
    }

    /// Test @Persistable with multiple indexes
    @Test("@Persistable with multiple indexes")
    func modelWithMultipleIndexes() throws {
        // Verify multiple indexes
        let indexes = try Product.indexDescriptors
        #expect(indexes.count == 2)

        // First index: category
        let categoryIndex = indexes[0]
        #expect(categoryIndex.name == "Product_category")
        #expect(categoryIndex.fieldNames == ["category"])
        #expect(categoryIndex.kind.fieldNames == ["category"])
        #expect(categoryIndex.kindIdentifier == "scalar")
        #expect(categoryIndex.isUnique == false)

        // Second index: category + price
        let compositeIndex = indexes[1]
        #expect(compositeIndex.name == "Product_category_price")
        #expect(compositeIndex.fieldNames == ["category", "price"])
        #expect(compositeIndex.kind.fieldNames == ["category", "price"])
        #expect(compositeIndex.kindIdentifier == "scalar")
    }

    /// Test @Persistable with custom index name
    @Test("@Persistable with custom index name")
    func modelWithCustomIndexName() throws {
        // Verify custom index name
        let indexes = try CustomNamedUser.indexDescriptors
        #expect(indexes.count == 1)
        let emailIndex = indexes[0]
        #expect(emailIndex.name == "user_email_idx")
    }

    /// Test @Persistable with custom type name
    @Test("@Persistable with custom type name")
    func modelWithCustomTypeName() {
        // Verify custom type name
        #expect(Member.persistableType == "User")
    }

    /// Test @Persistable with user-defined id
    @Test("@Persistable with user-defined id")
    func modelWithUserDefinedId() {
        // Verify user-defined id is used (with auto-generated default)
        let order = Order(orderID: 12345, amount: 99.99)
        #expect(order.id > 0)  // Auto-generated timestamp-based id
        #expect(Order.allFields.contains("id"))
    }

    /// Test @Persistable fieldNumber generation
    @Test("fieldNumber method generates sequential numbers")
    func fieldNumberGeneration() {
        // Verify field numbers (id is first if auto-generated)
        #expect(FieldNumberUser.fieldNumber(for: "id") == 1)
        #expect(FieldNumberUser.fieldNumber(for: "email") == 2)
        #expect(FieldNumberUser.fieldNumber(for: "name") == 3)
        #expect(FieldNumberUser.fieldNumber(for: "nonexistent") == nil)
    }

    /// Test @Persistable with different IndexKinds
    @Test("@Persistable with different IndexKind types")
    func modelWithDifferentIndexKinds() throws {
        // Verify different index kinds
        let indexes = try Analytics.indexDescriptors
        #expect(indexes.count == 3)

        let scalarIndex = indexes[0]
        #expect(scalarIndex.kindIdentifier == "scalar")

        let countIndex = indexes[1]
        #expect(countIndex.kindIdentifier == "count")

        let sumIndex = indexes[2]
        #expect(sumIndex.kindIdentifier == "sum")
    }

    /// Test @Persistable Codable conformance
    @Test("@Persistable generates Codable conformance")
    func modelCodableConformance() throws {
        let user = CodableUser(email: "test@example.com", name: "Alice")

        // Verify Codable works
        let encoder = JSONEncoder()
        let data = try encoder.encode(user)
        #expect(data.count > 0)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CodableUser.self, from: data)
        #expect(decoded.id == user.id)
        #expect(decoded.email == user.email)
        #expect(decoded.name == user.name)
    }

    /// Test @Persistable Sendable conformance
    @Test("@Persistable generates Sendable conformance")
    func modelSendableConformance() {
        // This test verifies that the compiler accepts User as Sendable
        let _: any Sendable = SendableUser(email: "test@example.com")
    }

    /// Test @Persistable init without id parameter
    @Test("@Persistable init does not include id parameter")
    func initWithoutIdParameter() {
        // Create user without specifying id
        let user = BasicUser(email: "test@example.com", name: "Alice")

        // id should be auto-generated (ULID format: 26 characters)
        #expect(user.id.count == 26)
        #expect(!user.id.isEmpty)
    }

    /// Test @Persistable dynamic member lookup
    @Test("@Persistable supports dynamic member lookup")
    func dynamicMemberLookup() {
        let user = BasicUser(email: "test@example.com", name: "Alice")

        // Access fields via dynamic member lookup
        #expect(user[dynamicMember: "email"] as? String == "test@example.com")
        #expect(user[dynamicMember: "name"] as? String == "Alice")
        #expect(user[dynamicMember: "nonexistent"] == nil)
    }

    @Test("@Persistable only treats instance stored properties as persisted fields")
    func staticAndComputedMembersAreNotPersistedFields() throws {
        let model = StaticAndComputedMemberModel(email: "test@example.com", name: "Alice")

        #expect(StaticAndComputedMemberModel.allFields == ["id", "email", "name"])
        #expect(StaticAndComputedMemberModel.fieldNumber(for: "id") == 1)
        #expect(StaticAndComputedMemberModel.fieldNumber(for: "email") == 2)
        #expect(StaticAndComputedMemberModel.fieldNumber(for: "name") == 3)
        #expect(StaticAndComputedMemberModel.fieldNumber(for: "displayName") == nil)
        #expect(StaticAndComputedMemberModel.fieldNumber(for: "seedData") == nil)
        #expect(StaticAndComputedMemberModel.fieldNumber(for: "supportedScopes") == nil)

        #expect(model[dynamicMember: "email"] as? String == "test@example.com")
        #expect(model[dynamicMember: "displayName"] == nil)
        #expect(model[dynamicMember: "seedData"] == nil)
        #expect(StaticAndComputedMemberModel.seedData.isEmpty)

        let data = try JSONEncoder().encode(model)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("email"))
        #expect(json.contains("name"))
        #expect(!json.contains("displayName"))
        #expect(!json.contains("seedData"))
        #expect(!json.contains("supportedScopes"))

        let decoded = try JSONDecoder().decode(StaticAndComputedMemberModel.self, from: data)
        #expect(decoded.email == model.email)
        #expect(decoded.name == model.name)
        #expect(decoded.displayName == "Alice <test@example.com>")
    }

    @Test("@Persistable resolves protocol-extension KeyPath field names")
    func protocolExtensionKeyPathFieldNames() throws {
        let schema = try Schema([MacroPolymorphicArticle.self, MacroPolymorphicReport.self])
        let articleDescriptor = try #require(
            schema.polymorphicIndexDescriptors(
                identifier: MacroPolymorphicArticle.polymorphableType,
                memberType: MacroPolymorphicArticle.self
            ).first
        )
        let reportDescriptor = try #require(
            schema.polymorphicIndexDescriptors(
                identifier: MacroPolymorphicReport.polymorphableType,
                memberType: MacroPolymorphicReport.self
            ).first
        )

        #expect(articleDescriptor.fieldNames == ["title"])
        #expect(reportDescriptor.fieldNames == ["title"])
        #expect(articleDescriptor.kind.identifier == "scalar")
        #expect(reportDescriptor.kind.identifier == "scalar")
        #expect(articleDescriptor.kind.fieldNames == ["title"])
        #expect(reportDescriptor.kind.fieldNames == ["title"])
    }

    @Test("@Polymorphable macro participates in schema construction")
    func polymorphableMacroParticipatesInSchemaConstruction() throws {
        let schema = try Schema([
            MacroGeneratedPolymorphicArticle.self,
            MacroGeneratedPolymorphicReport.self
        ])

        #expect(MacroGeneratedPolymorphicArticle.polymorphableType == "MacroGeneratedPolymorphicDocument")
        #expect(MacroGeneratedPolymorphicReport.polymorphableType == "MacroGeneratedPolymorphicDocument")

        let group = try #require(schema.polymorphicGroup(identifier: "MacroGeneratedPolymorphicDocument"))
        #expect(group.identifier == "MacroGeneratedPolymorphicDocument")
        #expect(group.memberTypeNames == [
            "MacroGeneratedPolymorphicArticle",
            "MacroGeneratedPolymorphicReport"
        ])
        #expect(schema.polymorphicIndexCatalog(identifier: group.identifier).isEmpty)
    }

    // MARK: - @Transient Tests

    /// Test @Transient excludes fields from allFields
    @Test("@Transient excludes fields from allFields")
    func transientExcludesFromAllFields() {
        // allFields should include: id, email, name
        // allFields should NOT include: cachedDisplayName, sessionToken, isOnline
        #expect(TransientUser.allFields.contains("id"))
        #expect(TransientUser.allFields.contains("email"))
        #expect(TransientUser.allFields.contains("name"))
        #expect(!TransientUser.allFields.contains("cachedDisplayName"))
        #expect(!TransientUser.allFields.contains("sessionToken"))
        #expect(!TransientUser.allFields.contains("isOnline"))
        #expect(TransientUser.allFields.count == 3)
    }

    /// Test @Transient excludes fields from subscript
    @Test("@Transient excludes fields from subscript")
    func transientExcludesFromSubscript() {
        let user = TransientUser(email: "test@example.com", name: "Alice")

        // Persisted fields should be accessible
        #expect(user[dynamicMember: "email"] as? String == "test@example.com")
        #expect(user[dynamicMember: "name"] as? String == "Alice")

        // Transient fields should return nil via subscript
        #expect(user[dynamicMember: "cachedDisplayName"] == nil)
        #expect(user[dynamicMember: "sessionToken"] == nil)
        #expect(user[dynamicMember: "isOnline"] == nil)
    }

    /// Test @Transient fields are not in init
    @Test("@Transient fields are excluded from init")
    func transientExcludesFromInit() {
        // This should compile - init only has email and name parameters
        let user = TransientUser(email: "test@example.com", name: "Alice")
        #expect(user.email == "test@example.com")
        #expect(user.name == "Alice")

        // Transient fields use their default values
        #expect(user.cachedDisplayName == nil)
        #expect(user.sessionToken == "")
        #expect(user.isOnline == false)
    }

    /// Test @Transient fields can still be accessed directly
    @Test("@Transient fields are accessible directly")
    func transientFieldsAccessible() {
        var user = TransientUser(email: "test@example.com", name: "Alice")

        // Can modify transient fields directly
        user.cachedDisplayName = "Alice <test@example.com>"
        user.sessionToken = "abc123"
        user.isOnline = true

        #expect(user.cachedDisplayName == "Alice <test@example.com>")
        #expect(user.sessionToken == "abc123")
        #expect(user.isOnline == true)
    }

    /// Test @Transient excludes fields from fieldNumber
    @Test("@Transient excludes fields from fieldNumber")
    func transientExcludesFromFieldNumber() {
        // Persisted fields have field numbers
        #expect(TransientUser.fieldNumber(for: "id") == 1)
        #expect(TransientUser.fieldNumber(for: "email") == 2)
        #expect(TransientUser.fieldNumber(for: "name") == 3)

        // Transient fields have no field number
        #expect(TransientUser.fieldNumber(for: "cachedDisplayName") == nil)
        #expect(TransientUser.fieldNumber(for: "sessionToken") == nil)
        #expect(TransientUser.fieldNumber(for: "isOnline") == nil)
    }

    /// Test @Transient with Codable serialization
    @Test("@Transient excludes fields from Codable")
    func transientExcludesFromCodable() throws {
        var user = TransientUser(email: "test@example.com", name: "Alice")
        user.cachedDisplayName = "Should not be encoded"
        user.sessionToken = "secret-token"
        user.isOnline = true

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(user)
        let json = String(data: data, encoding: .utf8)!

        // Transient fields should not be in JSON
        #expect(!json.contains("cachedDisplayName"))
        #expect(!json.contains("sessionToken"))
        #expect(!json.contains("isOnline"))

        // Persisted fields should be in JSON
        #expect(json.contains("email"))
        #expect(json.contains("name"))

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TransientUser.self, from: data)

        // Persisted fields are restored
        #expect(decoded.email == "test@example.com")
        #expect(decoded.name == "Alice")

        // Transient fields have default values (not the encoded values)
        #expect(decoded.cachedDisplayName == nil)
        #expect(decoded.sessionToken == "")
        #expect(decoded.isOnline == false)
    }
}

// MARK: - Test Structs (File Scope)

@Persistable
struct BasicUser {
    var email: String
    var name: String
}

@Persistable
struct StaticAndComputedMemberModel {
    static let supportedScopes = ["public", "private"]
    static var seedData: [StaticAndComputedMemberModel] { [] }

    var email: String
    var name: String
    var displayName: String { "\(name) <\(email)>" }
}

@Persistable
struct IndexedUser {
    #Index(ScalarIndexKind<IndexedUser>(fields: [\.email]), unique: true)

    var email: String
    var name: String
}

@Persistable
struct Product {
    #Index(ScalarIndexKind<Product>(fields: [\.category]))
    #Index(ScalarIndexKind<Product>(fields: [\.category, \.price]))

    var category: String
    var price: Double
    var name: String
}

@Persistable
struct CustomNamedUser {
    #Index(ScalarIndexKind<CustomNamedUser>(fields: [\.email]), name: "user_email_idx")

    var email: String
}

@Persistable(type: "User")
struct Member {
    var name: String
}

@Persistable
struct Order {
    var id: Int64 = Int64(Date().timeIntervalSince1970 * 1000)  // User-defined id with default
    var orderID: Int64
    var amount: Double
}

@Persistable
struct FieldNumberUser {
    var email: String
    var name: String
}

@Persistable
struct Analytics {
    #Index(ScalarIndexKind<Analytics>(fields: [\.category]))
    #Index(CountIndexKind<Analytics>(groupBy: [\.category]))
    #Index(SumIndexKind<Analytics, Double>(groupBy: [\.category], value: \.value))

    var category: String
    var value: Double
}

@Persistable
struct CodableUser {
    var email: String
    var name: String
}

@Persistable
struct SendableUser {
    var email: String
}

// MARK: - @Transient Tests

@Persistable
struct TransientUser {
    var email: String
    var name: String

    @Transient
    var cachedDisplayName: String?  // Optional transient (nil default)

    @Transient
    var sessionToken: String = ""   // Transient with explicit default

    @Transient
    var isOnline: Bool = false      // Transient boolean
}

protocol MacroPolymorphicDocument: Polymorphable {
    var id: String { get }
    var title: String { get }
}

extension MacroPolymorphicDocument {
    static var polymorphableType: String { "MacroPolymorphicDocument" }

    static var polymorphicDirectoryPathComponents: [DirectoryPathComponent] {
        [.staticPath("macro-polymorphic-documents")]
    }

    static var polymorphicIndexDescriptors: [IndexDescriptor] {
        get throws(IndexDeclarationError) {
            try [
                IndexDescriptor(
                    name: "MacroPolymorphicDocument_title",
                    keyPaths: [\Self.title],
                    kind: ScalarIndexKind<Self>(fields: [\Self.title])
                )
            ]
        }
    }
}

@Persistable
struct MacroPolymorphicArticle: MacroPolymorphicDocument {
    #Directory<MacroPolymorphicArticle>("macro-polymorphic-articles")

    var title: String
}

@Persistable
struct MacroPolymorphicReport: MacroPolymorphicDocument {
    #Directory<MacroPolymorphicReport>("macro-polymorphic-reports")

    var title: String
}

@Polymorphable
protocol MacroGeneratedPolymorphicDocument: Polymorphable {
    var id: String { get }
    var title: String { get }
}

@Persistable
struct MacroGeneratedPolymorphicArticle: MacroGeneratedPolymorphicDocument {
    var title: String
}

@Persistable
struct MacroGeneratedPolymorphicReport: MacroGeneratedPolymorphicDocument {
    var title: String
}
