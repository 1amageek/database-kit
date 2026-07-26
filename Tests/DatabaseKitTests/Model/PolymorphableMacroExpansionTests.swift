import DatabaseTypes
import Testing
import SwiftSyntaxMacrosTestSupport
import DatabaseKitMacros

@Suite("@Polymorphable Macro Expansion Tests")
struct PolymorphableMacroExpansionTests {

    @Test("@Polymorphable compiles protocol fields into logical selections")
    func compilesProtocolFieldsIntoLogicalSelections() {
        assertMacroExpansion(
            """
            @Polymorphable
            @PolymorphicDirectory("memory", "entities")
            @PolymorphicIndex(
                .scalar,
                fields: ["title"],
                storedFields: ["id"],
                unique: true,
                name: "MacroEntity_title"
            )
            protocol MacroEntity: Polymorphable<MacroEntityPolymorphicGroup> {
                var id: String { get }
                var title: String { get }
            }
            """,
            expandedSource: """
            protocol MacroEntity: Polymorphable<MacroEntityPolymorphicGroup> {
                var id: String { get }
                var title: String { get }
            }

            enum MacroEntityPolymorphicGroup: DatabaseKit.PolymorphicGroupDeclaration {
                static let identifier = "MacroEntity"

                static let directoryComponents: [DatabaseKit.DirectoryPathComponent] = [.staticPath("memory"), .staticPath("entities")]

                static let directoryLayer: DatabaseKit.DirectoryLayer = .default

                static let indexes: [DatabaseKit.PolymorphicIndexDefinition] = [
                    DatabaseKit.PolymorphicIndexDefinition(
                            name: "MacroEntity_title",
                            definition: .scalar,
                            fields: [DatabaseKit.PolymorphicIndexField(name: "title", order: .ascending)],
                            commonOptions: .init(unique: true),
                            storedFieldNames: ["id"]
                        )
                ]
            }
            """,
            macros: [
                "Polymorphable": PolymorphableMacro.self,
                "PolymorphicDirectory": PolymorphicDeclarationMarkerMacro.self,
                "PolymorphicIndex": PolymorphicDeclarationMarkerMacro.self,
            ]
        )
    }

    @Test("@Polymorphable preserves an explicit stable group identifier")
    func preservesExplicitGroupIdentifier() {
        assertMacroExpansion(
            """
            @Polymorphable(identifier: "Document")
            protocol VersionedDocument: Polymorphable<VersionedDocumentPolymorphicGroup> {
                var id: String { get }
            }
            """,
            expandedSource: """
            protocol VersionedDocument: Polymorphable<VersionedDocumentPolymorphicGroup> {
                var id: String { get }
            }

            enum VersionedDocumentPolymorphicGroup: DatabaseKit.PolymorphicGroupDeclaration {
                static let identifier = "Document"

                static let directoryComponents: [DatabaseKit.DirectoryPathComponent] = [.staticPath(identifier)]

                static let directoryLayer: DatabaseKit.DirectoryLayer = .default

                static let indexes: [DatabaseKit.PolymorphicIndexDefinition] = []
            }
            """,
            macros: [
                "Polymorphable": PolymorphableMacro.self,
            ]
        )
    }

    @Test("@Polymorphable rejects an empty group identifier")
    func rejectsEmptyGroupIdentifier() {
        assertMacroExpansion(
            """
            @Polymorphable(identifier: "")
            protocol VersionedDocument: Polymorphable<VersionedDocumentPolymorphicGroup> {
                var id: String { get }
            }
            """,
            expandedSource: """
            protocol VersionedDocument: Polymorphable<VersionedDocumentPolymorphicGroup> {
                var id: String { get }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Polymorphable identifier must be a nonempty string literal",
                    line: 1,
                    column: 16
                )
            ],
            macros: [
                "Polymorphable": PolymorphableMacro.self,
            ]
        )
    }

    @Test("@Polymorphable preserves a global count descriptor")
    func preservesGlobalCountDescriptor() {
        assertMacroExpansion(
            """
            @Polymorphable
            @PolymorphicIndex(
                .count,
                groupBy: []
            )
            protocol GlobalCountEntity: Polymorphable<GlobalCountEntityPolymorphicGroup> {
                var id: String { get }
            }
            """,
            expandedSource: """
            protocol GlobalCountEntity: Polymorphable<GlobalCountEntityPolymorphicGroup> {
                var id: String { get }
            }

            enum GlobalCountEntityPolymorphicGroup: DatabaseKit.PolymorphicGroupDeclaration {
                static let identifier = "GlobalCountEntity"

                static let directoryComponents: [DatabaseKit.DirectoryPathComponent] = [.staticPath(identifier)]

                static let directoryLayer: DatabaseKit.DirectoryLayer = .default

                static let indexes: [DatabaseKit.PolymorphicIndexDefinition] = [
                    DatabaseKit.PolymorphicIndexDefinition(
                            name: "GlobalCountEntity_count",
                            definition: .count,
                            fields: [],
                            commonOptions: .init(),
                            storedFieldNames: []
                        )
                ]
            }
            """,
            macros: [
                "Polymorphable": PolymorphableMacro.self,
                "PolymorphicIndex": PolymorphicDeclarationMarkerMacro.self,
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
                    message: "@Polymorphable protocol 'MacroEntity' must inherit from Polymorphable<MacroEntityPolymorphicGroup>",
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
            @PolymorphicIndex(.scalar, fields: ["missing"])
            protocol MacroEntity: Polymorphable<MacroEntityPolymorphicGroup> {
                var id: String { get }
            }
            """,
            expandedSource: """
            protocol MacroEntity: Polymorphable<MacroEntityPolymorphicGroup> {
                var id: String { get }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Polymorphic index field 'missing' is not declared by protocol 'MacroEntity'",
                    line: 2,
                    column: 1
                )
            ],
            macros: [
                "Polymorphable": PolymorphableMacro.self,
                "PolymorphicIndex": PolymorphicDeclarationMarkerMacro.self,
            ]
        )
    }
}
