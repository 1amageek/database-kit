import DatabaseTypes
import Testing
import SwiftSyntaxMacrosTestSupport
import DatabaseKitMacros

@Suite("@Polymorphable Macro Expansion Tests")
struct PolymorphableMacroExpansionTests {

    @Test("@Polymorphable compiles protocol KeyPaths into logical field selections")
    func compilesProtocolKeyPathsIntoLogicalFieldSelections() {
        assertMacroExpansion(
            """
            @Polymorphable
            protocol MacroEntity: Polymorphable {
                var id: String { get }
                var title: String { get }

                #Directory<Self>("memory", "entities")
                #PolymorphicIndex(
                    .scalar,
                    fields: ["title"],
                    storedFields: ["id"],
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
                #PolymorphicIndex(
                    .scalar,
                    fields: ["title"],
                    storedFields: ["id"],
                    unique: true,
                    name: "MacroEntity_title"
                )
            }

            extension MacroEntity {
                public static var polymorphableType: String {
                    "MacroEntity"
                }
                public static var polymorphicDirectoryPathComponents: [DirectoryPathComponent] {
                    [.staticPath("memory"), .staticPath("entities")]
                }
                public static var polymorphicDirectoryLayer: DatabaseKit.DirectoryLayer {
                    .default
                }
                public static var polymorphicIndexes: [PolymorphicIndexDefinition] {
                    [
                        PolymorphicIndexDefinition(
                            name: "MacroEntity_title",
                            definition: .scalar,
                            fields: [PolymorphicIndexField(name: "title", order: .ascending)],
                            commonOptions: .init(unique: true),
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

    @Test("@Polymorphable preserves a global count descriptor")
    func preservesGlobalCountDescriptor() {
        assertMacroExpansion(
            """
            @Polymorphable
            protocol GlobalCountEntity: Polymorphable {
                var id: String { get }

                #PolymorphicIndex(
                    .count,
                    groupBy: []
                )
            }
            """,
            expandedSource: """
            protocol GlobalCountEntity: Polymorphable {
                var id: String { get }

                #PolymorphicIndex(
                    .count,
                    groupBy: []
                )
            }

            extension GlobalCountEntity {
                public static var polymorphableType: String {
                    "GlobalCountEntity"
                }
                public static var polymorphicDirectoryPathComponents: [DirectoryPathComponent] {
                    [.staticPath(polymorphableType)]
                }
                public static var polymorphicDirectoryLayer: DatabaseKit.DirectoryLayer {
                    .default
                }
                public static var polymorphicIndexes: [PolymorphicIndexDefinition] {
                    [
                        PolymorphicIndexDefinition(
                            name: "GlobalCountEntity_count",
                            definition: .count,
                            fields: [],
                            commonOptions: .init(),
                            storedFieldNames: []
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

    @Test("@Polymorphable rejects index fields absent from the protocol")
    func rejectsUnknownProtocolIndexFields() {
        assertMacroExpansion(
            """
            @Polymorphable
            protocol MacroEntity: Polymorphable {
                var id: String { get }

                #PolymorphicIndex(.scalar, fields: ["missing"])
            }
            """,
            expandedSource: """
            protocol MacroEntity: Polymorphable {
                var id: String { get }

                #PolymorphicIndex(.scalar, fields: ["missing"])
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Polymorphic index field 'missing' is not declared by protocol 'MacroEntity'",
                    line: 5,
                    column: 5
                )
            ],
            macros: [
                "Polymorphable": PolymorphableMacro.self
            ]
        )
    }
}
