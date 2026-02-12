import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// `@Ontology` マクロの実装。
///
/// OWL オントロジークラスと Persistable 型を紐付ける。
/// `ontologyClassIRI` と `ontologyPropertyDescriptors` を生成し、
/// `OntologyEntity` プロトコル準拠を追加する。
public struct OntologyMacro: MemberMacro, ExtensionMacro {

    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OntologyMacroErrorMessage(
                        "@Ontology can only be applied to structs"
                    )
                )
            ])
        }

        // IRI 文字列を取得
        guard let arguments = node.arguments,
              let labeledList = arguments.as(LabeledExprListSyntax.self),
              let firstArg = labeledList.first else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OntologyMacroErrorMessage(
                        "@Ontology requires an IRI string argument. " +
                        "Example: @Ontology(\"http://example.org/onto#Employee\")"
                    )
                )
            ])
        }

        let iriExpr = firstArg.expression.description.trimmingCharacters(in: .whitespaces)
        guard iriExpr.hasPrefix("\"") && iriExpr.hasSuffix("\"") else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(firstArg),
                    message: OntologyMacroErrorMessage(
                        "@Ontology argument must be a string literal (IRI). " +
                        "Found: \(iriExpr)"
                    )
                )
            ])
        }
        let iri = String(iriExpr.dropFirst().dropLast())

        let structName = structDecl.name.text

        // @Property 付きフィールドを収集
        var ontologyProperties: [(fieldName: String, iri: String, label: String?, targetTypeName: String?, targetFieldName: String?)] = []

        for member in structDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                guard let propertyAttr = getPropertyAttribute(varDecl) else { continue }
                let info = extractPropertyInfo(from: propertyAttr)

                for binding in varDecl.bindings {
                    if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        let fieldName = pattern.identifier.text
                        ontologyProperties.append((
                            fieldName: fieldName,
                            iri: info.iri,
                            label: info.label,
                            targetTypeName: info.targetTypeName,
                            targetFieldName: info.targetFieldName
                        ))
                    }
                }
            }
        }

        var decls: [DeclSyntax] = []

        // ontologyClassIRI 生成
        let ontologyClassDecl: DeclSyntax = """
            public static var ontologyClassIRI: String { "\(raw: iri)" }
            """
        decls.append(ontologyClassDecl)

        // ontologyPropertyDescriptors 生成
        var descriptorInits: [String] = []
        for prop in ontologyProperties {
            let descriptorName = "\(structName)_\(prop.fieldName)"
            let labelLiteral = prop.label.map { "\"\($0)\"" } ?? "nil"
            let targetTypeLiteral = prop.targetTypeName.map { "\"\($0)\"" } ?? "nil"
            let targetFieldLiteral = prop.targetFieldName.map { "\"\($0)\"" } ?? "nil"

            let init_ = """
                OntologyPropertyDescriptor(
                    name: "\(descriptorName)",
                    fieldName: "\(prop.fieldName)",
                    iri: "\(prop.iri)",
                    label: \(labelLiteral),
                    targetTypeName: \(targetTypeLiteral),
                    targetFieldName: \(targetFieldLiteral)
                )
            """
            descriptorInits.append(init_)
        }

        let descriptorsArray = descriptorInits.isEmpty
            ? "[]"
            : "[\n            \(descriptorInits.joined(separator: ",\n            "))\n        ]"

        let descriptorsDecl: DeclSyntax = """
            public static var ontologyPropertyDescriptors: [OntologyPropertyDescriptor] { \(raw: descriptorsArray) }
            """
        decls.append(descriptorsDecl)

        return decls
    }

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let conformanceExt: DeclSyntax = """
            extension \(type.trimmed): OntologyEntity {}
            """

        if let extensionDecl = conformanceExt.as(ExtensionDeclSyntax.self) {
            return [extensionDecl]
        }

        return []
    }
}

/// @Ontology マクロのエラーメッセージ
struct OntologyMacroErrorMessage: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(_ message: String) {
        self.message = message
        self.diagnosticID = MessageID(domain: "GraphMacros", id: message)
        self.severity = .error
    }
}
