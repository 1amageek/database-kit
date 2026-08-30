import Testing
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosTestSupport
@testable import DatabaseKitMacros

/// Tests for the shared `#Directory` declaration parser.
///
/// The freestanding `#Directory` macro validates a declaration and the
/// `@Persistable` macro compiles the same call. Both parse it here, so these
/// tests own the contract that decides which declarations exist at all.
@Suite("#Directory Declaration Macro Parsing Tests")
struct DirectoryDeclarationMacroParsingTests {

    // MARK: - Accepted declarations

    @Test("A static and dynamic declaration compiles in written order")
    func compilesStaticAndDynamicComponents() throws {
        let declaration = try parseDirectory(
            #"#Directory<User>("tenants", \User.tenantID, "users", layer: .partition)"#
        )

        #expect(declaration.componentExpressions == [
            #".staticPath("tenants")"#,
            #".dynamicField(fieldName: "tenantID")"#,
            #".staticPath("users")"#
        ])
        #expect(declaration.dynamicFieldNames == ["tenantID"])
        #expect(declaration.layerExpression == ".partition")
    }

    @Test("An absent layer argument resolves the default layer")
    func resolvesDefaultLayerWhenAbsent() throws {
        let declaration = try parseDirectory(#"#Directory<User>("app", "users")"#)

        #expect(declaration.componentExpressions == [
            #".staticPath("app")"#,
            #".staticPath("users")"#
        ])
        #expect(declaration.dynamicFieldNames.isEmpty)
        #expect(declaration.layerExpression == ".default")
    }

    @Test("A qualified DirectoryLayer case resolves the same layer")
    func resolvesQualifiedLayerCase() throws {
        let declaration = try parseDirectory(
            #"#Directory<User>(\User.tenantID, layer: DirectoryLayer.partition)"#
        )

        #expect(declaration.layerExpression == ".partition")
    }

    // MARK: - Rejected layer arguments

    @Test("A layer argument that is not a DirectoryLayer case is rejected")
    func rejectsNonMemberAccessLayer() {
        #expect(throws: DiagnosticsError.self) {
            _ = try parseDirectory(#"#Directory<User>("users", layer: resolvedLayer)"#)
        }
    }

    @Test("A layer argument naming an undeclared case is rejected")
    func rejectsUnknownLayerCase() {
        #expect(throws: DiagnosticsError.self) {
            _ = try parseDirectory(#"#Directory<User>("users", layer: .archived)"#)
        }
    }

    @Test("A repeated layer argument is rejected")
    func rejectsRepeatedLayerArgument() {
        #expect(throws: DiagnosticsError.self) {
            _ = try parseDirectory(
                #"#Directory<User>(\User.tenantID, layer: .default, layer: .partition)"#
            )
        }
    }

    @Test("A partition layer without a dynamic component is rejected")
    func rejectsPartitionWithoutDynamicComponent() {
        #expect(throws: DiagnosticsError.self) {
            _ = try parseDirectory(#"#Directory<User>("users", layer: .partition)"#)
        }
    }

    // MARK: - Rejected key path components

    @Test("A key path rooted at another model is rejected")
    func rejectsForeignKeyPathRoot() {
        #expect(throws: DiagnosticsError.self) {
            _ = try parseDirectory(#"#Directory<User>("tenants", \Order.tenantID)"#)
        }
    }

    @Test("A key path written without an explicit root is rejected")
    func rejectsRootlessKeyPath() {
        #expect(throws: DiagnosticsError.self) {
            _ = try parseDirectory(#"#Directory<User>("tenants", \.tenantID)"#)
        }
    }

    @Test("A key path naming more than one property is rejected")
    func rejectsMultiComponentKeyPath() {
        #expect(throws: DiagnosticsError.self) {
            _ = try parseDirectory(#"#Directory<User>(\User.address.city)"#)
        }
    }

    @Test("A key path without a property component is rejected")
    func rejectsNonPropertyKeyPath() {
        #expect(throws: DiagnosticsError.self) {
            _ = try parseDirectory(#"#Directory<User>(\User.self)"#)
        }
    }

    // MARK: - Rejected static components

    @Test("An interpolated string literal is rejected")
    func rejectsInterpolatedStringLiteral() {
        #expect(throws: DiagnosticsError.self) {
            _ = try parseDirectory(##"#Directory<User>("users\(suffix)")"##)
        }
    }

    @Test("A string literal carrying an escape sequence is rejected")
    func rejectsEscapedStringLiteral() {
        #expect(throws: DiagnosticsError.self) {
            _ = try parseDirectory(##"#Directory<User>("a\nb")"##)
        }
    }

    @Test("An empty string literal is rejected")
    func rejectsEmptyStringLiteral() {
        #expect(throws: DiagnosticsError.self) {
            _ = try parseDirectory(#"#Directory<User>("")"#)
        }
    }

    @Test("A path component that is neither a literal nor a key path is rejected")
    func rejectsUnsupportedComponentExpression() {
        #expect(throws: DiagnosticsError.self) {
            _ = try parseDirectory(#"#Directory<User>(42)"#)
        }

        #expect(throws: DiagnosticsError.self) {
            _ = try parseDirectory(#"#Directory<User>(["app", "users"])"#)
        }
    }

    @Test("A labeled path component is rejected")
    func rejectsLabeledPathComponent() {
        #expect(throws: DiagnosticsError.self) {
            _ = try parseDirectory(#"#Directory<User>(path: "users")"#)
        }
    }

    // MARK: - Helpers

    private func parseDirectory(
        _ source: String,
        rootType: String = "User"
    ) throws -> ParsedDirectoryDeclaration {
        let declaration = DeclSyntax(stringLiteral: source)
        let macroDeclaration = try #require(
            declaration.as(MacroExpansionDeclSyntax.self)
        )
        return try parseDirectoryDeclaration(
            arguments: macroDeclaration.arguments,
            rootType: rootType,
            node: Syntax(macroDeclaration)
        )
    }
}
