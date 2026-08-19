import DatabaseTypes
import Testing
@testable import DatabaseKit

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
        #expect(emailIndex.name == "indexed_users_by_email")
        #expect(emailIndex.fieldNames == ["email"])
        #expect(emailIndex.type == .ordered)
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
        #expect(categoryIndex.name == "products_by_category")
        #expect(categoryIndex.fieldNames == ["category"])
        #expect(categoryIndex.type == .ordered)
        #expect(categoryIndex.isUnique == false)

        // Second index: category + price
        let compositeIndex = indexes[1]
        #expect(compositeIndex.name == "products_by_category_and_price")
        #expect(compositeIndex.fieldNames == ["category", "price"])
        #expect(compositeIndex.type == .ordered)
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

    @Test("generated fields carry typed canonical schema identity")
    func generatedTypedFields() {
        let email: Field<FieldNumberUser, String> = FieldNumberUser.fields.email
        let resolved: Field<FieldNumberUser, String> = #field(
            \FieldNumberUser.email
        )

        #expect(email == resolved)
        #expect(email.identity == FieldIdentity(name: "email", number: 2))
        #expect(email.type == .string)
        #expect(email.schema == FieldNumberUser.fieldSchemas[1])
    }

    /// Test @Persistable with different index definition families.
    @Test("@Persistable with different index definition families")
    func modelWithDifferentIndexDefinitionFamilies() throws {
        let indexes = try Analytics.indexDescriptors
        #expect(indexes.count == 3)

        let orderedIndex = indexes[0]
        #expect(orderedIndex.type == .ordered)

        let countIndex = indexes[1]
        #expect(countIndex.type == .aggregate(.count))

        let sumIndex = indexes[2]
        #expect(sumIndex.type == .aggregate(.sum))
    }

    @Test("@Persistable generates canonical field adaptation")
    func modelCanonicalFieldAdaptation() throws {
        let user = CodableUser(email: "test@example.com", name: "Alice")
        let fields = try PersistableFieldEncoder.encode(user)
        let decoded = try CodableUser.decodePersistedFields(fields)
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

    @Test("@Persistable preserves the model's explicit id policy")
    func explicitIDPolicy() {
        let user = BasicUser(email: "test@example.com", name: "Alice")
        #expect(user.id == "fixture-id")
    }

    @Test("@Persistable supports canonical field lookup")
    func canonicalFieldLookup() throws {
        let user = BasicUser(email: "test@example.com", name: "Alice")

        #expect(
            try user.persistedFieldValue(
                for: BasicUser.fields.email.identity
            ) == .string("test@example.com")
        )
        #expect(
            try user.persistedFieldValue(
                for: BasicUser.fields.name.identity
            ) == .string("Alice")
        )
        #expect(
            try user.persistedFieldValue(
                for: FieldIdentity(name: "nonexistent", number: 100)
            ) == nil
        )
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

        #expect(
            try model.persistedFieldValue(
                for: StaticAndComputedMemberModel.fields.email.identity
            ) == .string("test@example.com")
        )
        #expect(
            try model.persistedFieldValue(
                for: FieldIdentity(name: "displayName", number: 100)
            ) == nil
        )
        #expect(
            try model.persistedFieldValue(
                for: FieldIdentity(name: "seedData", number: 101)
            ) == nil
        )
        #expect(StaticAndComputedMemberModel.seedData.isEmpty)

        let fields = try PersistableFieldEncoder.encode(model)
        #expect(fields.map(\.name) == ["id", "email", "name"])
        let decoded = try StaticAndComputedMemberModel.decodePersistedFields(fields)
        #expect(decoded.email == model.email)
        #expect(decoded.name == model.name)
        #expect(decoded.displayName == "Alice <test@example.com>")
    }

    @Test("@Persistable excludes declaration comments from generated types")
    func declarationCommentsAreNotPartOfGeneratedTypes() throws {
        let model = CommentedFieldModel(
            status: "active",
            score: 42
        )

        #expect(CommentedFieldModel.fields.status.type == .string)
        #expect(CommentedFieldModel.fields.score.type == .int64)
        #expect(
            try model.persistedFieldValue(
                for: CommentedFieldModel.fields.status.identity
            ) == .string("active")
        )
        #expect(
            try model.persistedFieldValue(
                for: CommentedFieldModel.fields.score.identity
            ) == .int64(42)
        )
    }

    @Test("@Persistable resolves protocol-extension KeyPath field names")
    func protocolExtensionKeyPathFieldNames() throws {
        let schema = try Schema(
            entities: [
                try MacroPolymorphicArticle.schemaEntity,
                try MacroPolymorphicReport.schemaEntity,
            ]
        )
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
        #expect(articleDescriptor.type == .ordered)
        #expect(reportDescriptor.type == .ordered)
    }

    @Test("@Polymorphable macro participates in schema construction")
    func polymorphableMacroParticipatesInSchemaConstruction() throws {
        let schema = try Schema(
            entities: [
                try MacroGeneratedPolymorphicArticle.schemaEntity,
                try MacroGeneratedPolymorphicReport.schemaEntity,
            ]
        )

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

    @Test("@Transient excludes fields from canonical lookup")
    func transientExcludesFromCanonicalLookup() throws {
        let user = TransientUser(email: "test@example.com", name: "Alice")

        #expect(
            try user.persistedFieldValue(
                for: TransientUser.fields.email.identity
            ) == .string("test@example.com")
        )
        #expect(
            try user.persistedFieldValue(
                for: TransientUser.fields.name.identity
            ) == .string("Alice")
        )
        #expect(
            try user.persistedFieldValue(
                for: FieldIdentity(name: "cachedDisplayName", number: 100)
            ) == nil
        )
        #expect(
            try user.persistedFieldValue(
                for: FieldIdentity(name: "sessionToken", number: 101)
            ) == nil
        )
        #expect(
            try user.persistedFieldValue(
                for: FieldIdentity(name: "isOnline", number: 102)
            ) == nil
        )
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

    @Test("@Transient excludes fields from canonical persistence")
    func transientExcludesFromCanonicalPersistence() throws {
        var user = TransientUser(email: "test@example.com", name: "Alice")
        user.cachedDisplayName = "Should not be encoded"
        user.sessionToken = "secret-token"
        user.isOnline = true

        let fields = try PersistableFieldEncoder.encode(user)
        #expect(fields.map(\.name) == ["id", "email", "name"])
        let decoded = try TransientUser.decodePersistedFields(fields)

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
    var id: String = "fixture-id"
    var email: String
    var name: String
}

@Persistable
struct StaticAndComputedMemberModel {
    var id: String = "fixture-id"
    static let supportedScopes = ["public", "private"]
    static var seedData: [StaticAndComputedMemberModel] { [] }

    var email: String
    var name: String
    var displayName: String { "\(name) <\(email)>" }
}

@Persistable
struct CommentedFieldModel {
    var id: String = "fixture-id"
    var status: String  // Stored status label.
    var score: Int64    // Stable score value.
}

@Persistable
struct IndexedUser {
    var id: String = "fixture-id"
    #Index(.ordered(
        name: "indexed_users_by_email",
        keys: [.ascending(\IndexedUser.email)],
        unique: true
    ))

    var email: String
    var name: String
}

@Persistable
struct Product {
    var id: String = "fixture-id"
    #Index(.ordered(
        name: "products_by_category",
        keys: [.ascending(\Product.category)]
    ))
    #Index(.ordered(
        name: "products_by_category_and_price",
        keys: [
            .ascending(\Product.category),
            .ascending(\Product.price),
        ]
    ))

    var category: String
    var price: Double
    var name: String
}

@Persistable
struct CustomNamedUser {
    var id: String = "fixture-id"
    #Index(
        .ordered(
            name: "user_email_idx",
            keys: [.ascending(\CustomNamedUser.email)]
        )
    )

    var email: String
}

@Persistable(type: "User")
struct Member {
    var id: String = "fixture-id"
    var name: String
}

@Persistable
struct Order {
    var id: Int64 = 1
    var orderID: Int64
    var amount: Double
}

@Persistable
struct FieldNumberUser {
    var id: String = "fixture-id"
    var email: String
    var name: String
}

@Persistable
struct Analytics {
    var id: String = "fixture-id"
    #Index(.ordered(
        name: "analytics_by_category",
        keys: [.ascending(\Analytics.category)]
    ))
    #Index(.aggregate(
        name: "analytics_count_by_category",
        function: .count,
        groupBy: [.ascending(\Analytics.category)]
    ))
    #Index(.aggregate(
        name: "analytics_sum_by_category",
        function: .sum,
        groupBy: [.ascending(\Analytics.category)],
        value: \Analytics.value
    ))

    var category: String
    var value: Double
}

@Persistable
struct CodableUser {
    var id: String = "fixture-id"
    var email: String
    var name: String
}

@Persistable
struct SendableUser {
    var id: String = "fixture-id"
    var email: String
}

// MARK: - @Transient Tests

@Persistable
struct TransientUser {
    var id: String = "fixture-id"
    var email: String
    var name: String

    @Transient
    var cachedDisplayName: String?  // Optional transient (nil default)

    @Transient
    var sessionToken: String = ""   // Transient with explicit default

    @Transient
    var isOnline: Bool = false      // Transient boolean
}

enum MacroPolymorphicDocumentGroup: PolymorphicGroupDeclaration {
    static let identifier = "MacroPolymorphicDocument"
    static let directoryComponents: [DirectoryPathComponent] = [
        .staticPath("macro-polymorphic-documents")
    ]
    static let directoryLayer: DirectoryLayer = .default
    static let indexes: [IndexDeclaration<String>] = [
        .ordered(
            name: "MacroPolymorphicDocument_title",
            keys: [.ascending("title")]
        )
    ]
}

protocol MacroPolymorphicDocument:
    Polymorphable<MacroPolymorphicDocumentGroup>
{
    var id: String { get }
    var title: String { get }
}

@Persistable
struct MacroPolymorphicArticle: MacroPolymorphicDocument {
    var id: String = "fixture-id"
    #Directory<MacroPolymorphicArticle>("macro-polymorphic-articles")

    var title: String
}

@Persistable
struct MacroPolymorphicReport: MacroPolymorphicDocument {
    var id: String = "fixture-id"
    #Directory<MacroPolymorphicReport>("macro-polymorphic-reports")

    var title: String
}

@Polymorphable
protocol MacroGeneratedPolymorphicDocument:
    Polymorphable<MacroGeneratedPolymorphicDocumentPolymorphicGroup>
{
    var id: String { get }
    var title: String { get }
}

@Persistable
struct MacroGeneratedPolymorphicArticle: MacroGeneratedPolymorphicDocument {
    var id: String = "fixture-id"
    var title: String
}

@Persistable
struct MacroGeneratedPolymorphicReport: MacroGeneratedPolymorphicDocument {
    var id: String = "fixture-id"
    var title: String
}
