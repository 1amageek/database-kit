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
                .ordered(
                    name: "MacroEntity_title",
                    keys: [.ascending("title")],
                    includedFields: ["id"],
                    unique: true
                )
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

                static let indexes: [DatabaseKit.IndexDeclaration<String>] = [
                    .ordered(
                            name: "MacroEntity_title",
                            keys: [.ascending("title")],
                            includedFields: ["id"],
                            unique: true
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

    @Test("@Polymorphable preserves a qualified directory layer expression")
    func preservesQualifiedDirectoryLayerExpression() {
        assertMacroExpansion(
            """
            @Polymorphable
            @PolymorphicDirectory(
                "memory",
                layer: DatabaseKit.DirectoryLayer.default
            )
            protocol QualifiedDirectoryEntity: Polymorphable<QualifiedDirectoryEntityPolymorphicGroup> {
            }
            """,
            expandedSource: """
            protocol QualifiedDirectoryEntity: Polymorphable<QualifiedDirectoryEntityPolymorphicGroup> {
            }

            enum QualifiedDirectoryEntityPolymorphicGroup: DatabaseKit.PolymorphicGroupDeclaration {
                static let identifier = "QualifiedDirectoryEntity"

                static let directoryComponents: [DatabaseKit.DirectoryPathComponent] = [.staticPath("memory")]

                static let directoryLayer: DatabaseKit.DirectoryLayer = DatabaseKit.DirectoryLayer.default

                static let indexes: [DatabaseKit.IndexDeclaration<String>] = []
            }
            """,
            macros: [
                "Polymorphable": PolymorphableMacro.self,
                "PolymorphicDirectory": PolymorphicDeclarationMarkerMacro.self,
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

                static let indexes: [DatabaseKit.IndexDeclaration<String>] = []
            }
            """,
            macros: [
                "Polymorphable": PolymorphableMacro.self,
            ]
        )
    }

    @Test("@Polymorphable preserves a raw group identifier")
    func preservesRawGroupIdentifier() {
        assertMacroExpansion(
            ##"""
            @Polymorphable(identifier: #"Document"#)
            protocol RawIdentifierDocument: Polymorphable<RawIdentifierDocumentPolymorphicGroup> {
                var id: String { get }
            }
            """##,
            expandedSource: """
            protocol RawIdentifierDocument: Polymorphable<RawIdentifierDocumentPolymorphicGroup> {
                var id: String { get }
            }

            enum RawIdentifierDocumentPolymorphicGroup: DatabaseKit.PolymorphicGroupDeclaration {
                static let identifier = "Document"

                static let directoryComponents: [DatabaseKit.DirectoryPathComponent] = [.staticPath(identifier)]

                static let directoryLayer: DatabaseKit.DirectoryLayer = .default

                static let indexes: [DatabaseKit.IndexDeclaration<String>] = []
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
                .aggregate(
                    name: "GlobalCountEntity_count",
                    function: .count
                )
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

                static let indexes: [DatabaseKit.IndexDeclaration<String>] = [
                    .aggregate(
                            name: "GlobalCountEntity_count",
                            function: .count
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

    @Test("@Polymorphable preserves fields for schema-time validation")
    func preservesFieldsForSchemaValidation() {
        assertMacroExpansion(
            """
            @Polymorphable
            @PolymorphicIndex(.ordered(
                name: "macro_by_missing",
                keys: [.ascending("missing")]
            ))
            protocol MacroEntity: Polymorphable<MacroEntityPolymorphicGroup> {
                var id: String { get }
            }
            """,
            expandedSource: """
            protocol MacroEntity: Polymorphable<MacroEntityPolymorphicGroup> {
                var id: String { get }
            }

            enum MacroEntityPolymorphicGroup: DatabaseKit.PolymorphicGroupDeclaration {
                static let identifier = "MacroEntity"

                static let directoryComponents: [DatabaseKit.DirectoryPathComponent] = [.staticPath(identifier)]

                static let directoryLayer: DatabaseKit.DirectoryLayer = .default

                static let indexes: [DatabaseKit.IndexDeclaration<String>] = [
                    .ordered(
                        name: "macro_by_missing",
                        keys: [.ascending("missing")]
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
}
