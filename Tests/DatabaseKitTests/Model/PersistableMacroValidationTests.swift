import DatabaseTypes
import Testing
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosTestSupport
import DatabaseKitMacros
@testable import DatabaseKit

/// Tests for @Persistable macro validation and edge cases
@Suite("@Persistable Macro Validation Tests")
struct ModelMacroValidationTests {
    @Test("@Persistable selects PersistableEnum for enums")
    func selectsPersistableEnumConformance() {
        assertMacroExpansion(
            """
            @Persistable
            enum Status: String {
                case active
                case inactive
            }
            """,
            expandedSource: """
            enum Status: String {
                case active
                case inactive

                public static var allCases: [Self] {
                    [.active, .inactive]
                }
            }

            extension Status: PersistableEnum {
            }
            """,
            macroSpecs: [
                "Persistable": MacroSpec(
                    type: PersistableMacro.self,
                    conformances: ["Persistable", "PersistableEnum"]
                )
            ]
        )
    }

    @Test("@Persistable type parameter rejects enums")
    func rejectsEnumTypeParameter() {
        assertMacroExpansion(
            """
            @Persistable(type: "StableStatus")
            enum Status: String {
                case active
            }
            """,
            expandedSource: """
            enum Status: String {
                case active
            }

            extension Status: PersistableEnum {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Persistable(type:) is only available for structs",
                    line: 1,
                    column: 14
                )
            ],
            macroSpecs: [
                "Persistable": MacroSpec(
                    type: PersistableMacro.self,
                    conformances: ["Persistable", "PersistableEnum"]
                )
            ]
        )
    }

    @Test("@Persistable rejects enum case availability")
    func rejectsEnumCaseAvailability() {
        assertMacroExpansion(
            """
            @Persistable
            enum Status: String {
                @available(*, unavailable)
                case retired
            }
            """,
            expandedSource: """
            enum Status: String {
                @available(*, unavailable)
                case retired
            }

            extension Status: PersistableEnum {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Persistable enum cases cannot have availability attributes",
                    line: 3,
                    column: 5
                )
            ],
            macroSpecs: [
                "Persistable": MacroSpec(
                    type: PersistableMacro.self,
                    conformances: ["Persistable", "PersistableEnum"]
                )
            ]
        )
    }

    @Test("@Persistable rejects enum associated values")
    func rejectsEnumAssociatedValues() {
        assertMacroExpansion(
            """
            @Persistable
            enum Status: String {
                case custom(String)
            }
            """,
            expandedSource: """
            enum Status: String {
                case custom(String)
            }

            extension Status: PersistableEnum {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Persistable enum cases cannot have associated values",
                    line: 3,
                    column: 10
                )
            ],
            macroSpecs: [
                "Persistable": MacroSpec(
                    type: PersistableMacro.self,
                    conformances: ["Persistable", "PersistableEnum"]
                )
            ]
        )
    }

    @Test("@Persistable preserves explicit allCases")
    func preservesExplicitAllCases() {
        assertMacroExpansion(
            """
            @Persistable
            enum Status: String {
                case active

                public static var allCases: [Self] {
                    [.active]
                }
            }
            """,
            expandedSource: """
            enum Status: String {
                case active

                public static var allCases: [Self] {
                    [.active]
                }
            }

            extension Status: PersistableEnum {
            }
            """,
            macroSpecs: [
                "Persistable": MacroSpec(
                    type: PersistableMacro.self,
                    conformances: ["Persistable", "PersistableEnum"]
                )
            ]
        )
    }

    @Test("@Persistable rejects platform-dependent integer storage")
    func rejectsPlatformDependentIntegerStorage() {
        assertMacroExpansion(
            """
            @Persistable
            struct PlatformIntegerDocument {
                var id: String
                var count: Int
            }
            """,
            expandedSource: """
            struct PlatformIntegerDocument {
                var id: String
                var count: Int
            }

            extension PlatformIntegerDocument: Persistable {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Persistable field 'count' uses Int. Persisted integer fields require an explicit fixed-width type.",
                    line: 1,
                    column: 1
                )
            ],
            macroSpecs: [
                "Persistable": MacroSpec(
                    type: PersistableMacro.self,
                    conformances: ["Persistable", "PersistableEnum"]
                )
            ]
        )
    }

    /// Test that indexDescriptors are correctly ordered
    @Test("Index descriptors maintain definition order")
    func indexDescriptorsOrder() throws {
        // Verify that indexes are in the order they were defined
        let descriptors = try OrderedIndexProduct.indexDescriptors
        #expect(descriptors.count == 3)
        #expect(descriptors[0].name == "OrderedIndexProduct_category")
        #expect(descriptors[1].name == "OrderedIndexProduct_price")
        #expect(descriptors[2].name == "OrderedIndexProduct_name")
    }

    /// Test that field numbers are stable
    @Test("Field numbers should be deterministic")
    func fieldNumbersStable() {
        // Field numbers should match field declaration order (id first if auto-generated)
        #expect(StableFieldUser.fieldNumber(for: "id") == 1)
        #expect(StableFieldUser.fieldNumber(for: "email") == 2)
        #expect(StableFieldUser.fieldNumber(for: "name") == 3)
        #expect(StableFieldUser.fieldNumber(for: "createdAt") == 4)
    }

    @Test("Explicit model id policy is preserved")
    func explicitModelIDPolicy() {
        let user = SimpleUser(email: "test@example.com")

        #expect(user.id == "fixture-id")

        // Verify metadata
        #expect(SimpleUser.persistableType == "SimpleUser")
        #expect(SimpleUser.allFields.first == "id")
    }

    /// Test @Persistable with custom type parameter
    @Test("@Persistable type parameter")
    func persistableTypeParameter() {
        // CustomTypeMember uses @Persistable(type: "CustomUser")
        #expect(CustomTypeMember.persistableType == "CustomUser")
    }

    /// Test user-defined id is preserved
    @Test("User-defined id is preserved")
    func userDefinedIdPreserved() {
        // UserDefinedIdModel has user-defined id with auto-generated default
        let model = UserDefinedIdModel(name: "Test")

        #expect(model.id > 0)  // Auto-generated timestamp-based id
        #expect(UserDefinedIdModel.allFields.contains("id"))
    }
}

// MARK: - Test Structs

@Persistable
struct OrderedIndexProduct {
    var id: String = "fixture-id"
    #Index(.scalar, fields: [\OrderedIndexProduct.category])
    #Index(.scalar, fields: [\OrderedIndexProduct.price])
    #Index(.scalar, fields: [\OrderedIndexProduct.name])

    var category: String
    var price: Double
    var name: String
}

@Persistable
struct StableFieldUser {
    var id: String = "fixture-id"
    var email: String
    var name: String
    var createdAt: Timestamp
}

@Persistable
struct SimpleUser {
    var id: String = "fixture-id"
    var email: String
}

@Persistable(type: "CustomUser")
struct CustomTypeMember {
    var id: String = "fixture-id"
    var name: String
}

@Persistable
struct UserDefinedIdModel {
    var id: Int64 = 1
    var name: String
}
