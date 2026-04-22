import Testing
import SwiftSyntaxMacrosTestSupport
import CoreMacros

@Suite("@Polymorphable Macro Expansion Tests")
struct PolymorphableMacroExpansionTests {

    @Test("@Polymorphable expands indexed protocol metadata with Self KeyPaths")
    func expandsIndexedProtocolMetadataWithSelfKeyPaths() {
        assertMacroExpansion(
            """
            @Polymorphable
            protocol MacroEntity: Polymorphable {
                var id: String { get }
                var title: String { get }

                #Directory<Self>("memory", "entities")
                #Index(
                    ScalarIndexKind<Self>(fields: [\\Self.title]),
                    storedFields: [\\Self.id],
                    unique: true,
                    name: "MacroEntity_title"
                )
            }
            """,
            expandedSource: """
            protocol MacroEntity: Polymorphable {
                var id: String { get }
                var title: String { get }

                #Directory<Self>("memory", "entities")
                #Index(
                    ScalarIndexKind<Self>(fields: [\\Self.title]),
                    storedFields: [\\Self.id],
                    unique: true,
                    name: "MacroEntity_title"
                )
            }

            extension MacroEntity {
                public static var polymorphableType: String { "MacroEntity" }
                public static var polymorphicDirectoryPathComponents: [any DirectoryPathElement] { [Path("memory"), Path("entities")] }
                public static var polymorphicDirectoryLayer: Core.DirectoryLayer { .default }
                public static var polymorphicIndexDescriptors: [IndexDescriptor] {
                    [
                        IndexDescriptor(
                            name: "MacroEntity_title",
                            keyPaths: [\\Self.title],
                            kind: ScalarIndexKind<Self>(fields: [\\Self.title]),
                            commonOptions: .init(unique: true),
                            storedKeyPaths: [\\Self.id],
                            storedFieldNames: ["id"]
                        )
                    ]
                }
            }
            """,
            macros: [
                "Polymorphable": PolymorphableMacro.self
            ]
        )
    }

    @Test("@Polymorphable requires explicit Polymorphable inheritance")
    func requiresExplicitPolymorphableInheritance() {
        assertMacroExpansion(
            """
            @Polymorphable
            protocol MacroEntity {
            }
            """,
            expandedSource: """
            protocol MacroEntity {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Polymorphable protocols must explicitly inherit from Polymorphable",
                    line: 1,
                    column: 1
                )
            ],
            macros: [
                "Polymorphable": PolymorphableMacro.self
            ]
        )
    }
}
