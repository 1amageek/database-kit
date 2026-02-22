import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Implementation of the `@OWLObjectProperty` macro.
///
/// Binds a Persistable type to an OWL ObjectProperty, declaring
/// `from` and `to` endpoint fields. Generates `OWLObjectPropertyEntity`
/// protocol conformance and collects `@OWLDataProperty` metadata.
public struct OWLObjectPropertyMacro: MemberMacro, ExtensionMacro {

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
                    message: OWLObjectPropertyMacroErrorMessage(
                        "@OWLObjectProperty can only be applied to structs"
                    )
                )
            ])
        }

        // Extract arguments: (_ iri: String, from: KeyPath, to: KeyPath)
        guard let arguments = node.arguments,
              let labeledList = arguments.as(LabeledExprListSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OWLObjectPropertyMacroErrorMessage(
                        "@OWLObjectProperty requires (iri, from:, to:) arguments"
                    )
                )
            ])
        }

        var iri = ""
        var fromField = ""
        var toField = ""

        for (index, argument) in labeledList.enumerated() {
            let argLabel = argument.label?.text

            if index == 0 && argLabel == nil {
                // First unlabeled argument = IRI string
                let expr = argument.expression.description.trimmingCharacters(in: .whitespaces)
                guard expr.hasPrefix("\"") && expr.hasSuffix("\"") else {
                    throw DiagnosticsError(diagnostics: [
                        Diagnostic(
                            node: Syntax(argument),
                            message: OWLObjectPropertyMacroErrorMessage(
                                "@OWLObjectProperty first argument must be a string literal (IRI)"
                            )
                        )
                    ])
                }
                iri = String(expr.dropFirst().dropLast())
            } else if argLabel == "from" {
                let expr = argument.expression.description.trimmingCharacters(in: .whitespaces)
                if expr.hasPrefix("\"") && expr.hasSuffix("\"") {
                    fromField = String(expr.dropFirst().dropLast())
                }
            } else if argLabel == "to" {
                let expr = argument.expression.description.trimmingCharacters(in: .whitespaces)
                if expr.hasPrefix("\"") && expr.hasSuffix("\"") {
                    toField = String(expr.dropFirst().dropLast())
                }
            }
        }

        guard !iri.isEmpty else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OWLObjectPropertyMacroErrorMessage("@OWLObjectProperty requires an IRI string argument")
                )
            ])
        }
        guard !fromField.isEmpty else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OWLObjectPropertyMacroErrorMessage("@OWLObjectProperty requires a 'from:' KeyPath argument")
                )
            ])
        }
        guard !toField.isEmpty else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OWLObjectPropertyMacroErrorMessage("@OWLObjectProperty requires a 'to:' KeyPath argument")
                )
            ])
        }

        let structName = structDecl.name.text

        // Resolve namespace from IRI
        let namespace = extractNamespace(from: iri)

        // Collect @OWLDataProperty / @OWLProperty annotated fields
        var ontologyProperties: [(fieldName: String, iri: String, label: String?)] = []

        for member in structDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                guard let propertyAttr = getOWLDataPropertyAttribute(varDecl) else { continue }
                let info = extractOWLDataPropertyInfo(from: propertyAttr)

                for binding in varDecl.bindings {
                    if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        let fieldName = pattern.identifier.text
                        ontologyProperties.append((
                            fieldName: fieldName,
                            iri: resolvePropertyIRI(info.iri, namespace: namespace),
                            label: info.label
                        ))
                    }
                }
            }
        }

        var decls: [DeclSyntax] = []

        // Generate objectPropertyIRI
        let iriDecl: DeclSyntax = """
            public static var objectPropertyIRI: String { "\(raw: iri)" }
            """
        decls.append(iriDecl)

        // Generate fromFieldName
        let fromDecl: DeclSyntax = """
            public static var fromFieldName: String { "\(raw: fromField)" }
            """
        decls.append(fromDecl)

        // Generate toFieldName
        let toDecl: DeclSyntax = """
            public static var toFieldName: String { "\(raw: toField)" }
            """
        decls.append(toDecl)

        // Generate ontologyPropertyDescriptors
        var descriptorInits: [String] = []
        for prop in ontologyProperties {
            let descriptorName = "\(structName)_\(prop.fieldName)"
            let labelLiteral = prop.label.map { "\"\($0)\"" } ?? "nil"
            let init_ = """
                OWLDataPropertyDescriptor(
                    name: "\(descriptorName)",
                    fieldName: "\(prop.fieldName)",
                    iri: "\(prop.iri)",
                    label: \(labelLiteral)
                )
            """
            descriptorInits.append(init_)
        }

        let descriptorsArray = descriptorInits.isEmpty
            ? "[]"
            : "[\n            \(descriptorInits.joined(separator: ",\n            "))\n        ]"

        let descriptorsDecl: DeclSyntax = """
            public static var ontologyPropertyDescriptors: [OWLDataPropertyDescriptor] { \(raw: descriptorsArray) }
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
            extension \(type.trimmed): OWLObjectPropertyEntity {}
            """

        if let extensionDecl = conformanceExt.as(ExtensionDeclSyntax.self) {
            return [extensionDecl]
        }

        return []
    }

    // MARK: - Helpers

    /// Extract namespace from IRI (same logic as OWLClassMacro)
    private static func extractNamespace(from iri: String) -> String {
        if let colonIndex = iri.firstIndex(of: ":") {
            let afterColon = iri[iri.index(after: colonIndex)...]
            if !afterColon.hasPrefix("//") {
                return String(iri[...colonIndex])
            }
        }
        if let hashIndex = iri.lastIndex(of: "#") {
            return String(iri[...hashIndex])
        }
        if let slashIndex = iri.lastIndex(of: "/") {
            return String(iri[...slashIndex])
        }
        return "ex:"
    }

    /// Resolve property IRI with namespace
    private static func resolvePropertyIRI(_ rawIRI: String, namespace: String) -> String {
        if rawIRI.contains("://") { return rawIRI }
        if rawIRI.contains(":") { return rawIRI }
        return namespace + rawIRI
    }
}

/// Error message for @OWLObjectProperty macro
struct OWLObjectPropertyMacroErrorMessage: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(_ message: String) {
        self.message = message
        self.diagnosticID = MessageID(domain: "GraphMacros", id: message)
        self.severity = .error
    }
}
