import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Implementation of the `@OWLClass` macro.
///
/// Binds a Persistable type to an OWL class in the OntologyStore.
/// Generates `ontologyClassIRI` and `ontologyPropertyDescriptors`,
/// and adds `OWLClassEntity` protocol conformance.
public struct OWLClassMacro: MemberMacro, ExtensionMacro {

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
                    message: OWLClassMacroErrorMessage(
                        "@OWLClass can only be applied to structs"
                    )
                )
            ])
        }

        // Extract IRI string argument
        guard let arguments = node.arguments,
              let labeledList = arguments.as(LabeledExprListSyntax.self),
              let firstArg = labeledList.first else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OWLClassMacroErrorMessage(
                        "@OWLClass requires an IRI string argument. " +
                        "Example: @OWLClass(\"http://example.org/onto#Employee\")"
                    )
                )
            ])
        }

        let iriExpr = firstArg.expression.description.trimmingCharacters(in: .whitespaces)
        guard iriExpr.hasPrefix("\"") && iriExpr.hasSuffix("\"") else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(firstArg),
                    message: OWLClassMacroErrorMessage(
                        "@OWLClass argument must be a string literal (IRI). " +
                        "Found: \(iriExpr)"
                    )
                )
            ])
        }
        let rawIRI = String(iriExpr.dropFirst().dropLast())
        let namespace = Self.extractNamespace(from: rawIRI)
        let iri = Self.resolveClassIRI(rawIRI, namespace: namespace)

        let structName = structDecl.name.text

        // Collect @OWLDataProperty / @OWLProperty annotated fields
        var ontologyProperties: [(fieldName: String, iri: String, label: String?, targetTypeName: String?, targetFieldName: String?)] = []

        for member in structDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                guard let propertyAttr = getOWLDataPropertyAttribute(varDecl) else { continue }
                let info = extractOWLDataPropertyInfo(from: propertyAttr)

                for binding in varDecl.bindings {
                    if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        let fieldName = pattern.identifier.text
                        ontologyProperties.append((
                            fieldName: fieldName,
                            iri: Self.resolvePropertyIRI(info.iri, namespace: namespace),
                            label: info.label,
                            targetTypeName: info.targetTypeName,
                            targetFieldName: info.targetFieldName
                        ))
                    }
                }
            }
        }

        var decls: [DeclSyntax] = []

        // Generate ontologyClassIRI
        let ontologyClassDecl: DeclSyntax = """
            public static var ontologyClassIRI: String { "\(raw: iri)" }
            """
        decls.append(ontologyClassDecl)

        // Generate ontologyPropertyDescriptors
        var descriptorInits: [String] = []
        for prop in ontologyProperties {
            let descriptorName = "\(structName)_\(prop.fieldName)"
            let labelLiteral = prop.label.map { "\"\($0)\"" } ?? "nil"
            let targetTypeLiteral = prop.targetTypeName.map { "\"\($0)\"" } ?? "nil"
            let targetFieldLiteral = prop.targetFieldName.map { "\"\($0)\"" } ?? "nil"

            let init_ = """
                OWLDataPropertyDescriptor(
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
            public static var ontologyPropertyDescriptors: [OWLDataPropertyDescriptor] { \(raw: descriptorsArray) }
            """
        decls.append(descriptorsDecl)

        return decls
    }

    // MARK: - IRI Resolution

    /// Extract namespace from the `@OWLClass` IRI.
    ///
    /// - CURIE `"ex:Employee"` → `"ex:"`
    /// - Full IRI `"http://example.org/onto#Employee"` → `"http://example.org/onto#"`
    /// - Full IRI `"http://example.org/onto/Employee"` → `"http://example.org/onto/"`
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

    /// Resolve class IRI with namespace.
    ///
    /// Bare names (no `:`, `#`, `/`) get the default namespace `"ex:"` prepended.
    private static func resolveClassIRI(_ rawIRI: String, namespace: String) -> String {
        if rawIRI.contains(":") || rawIRI.contains("#") || rawIRI.contains("/") {
            return rawIRI
        }
        return namespace + rawIRI
    }

    /// Resolve property IRI with namespace.
    ///
    /// - Contains `"://"` → full IRI → keep as-is
    /// - Contains `":"` → CURIE → keep as-is
    /// - Otherwise → local name → prepend namespace
    private static func resolvePropertyIRI(_ rawIRI: String, namespace: String) -> String {
        if rawIRI.contains("://") { return rawIRI }
        if rawIRI.contains(":") { return rawIRI }
        return namespace + rawIRI
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
            extension \(type.trimmed): OWLClassEntity {}
            """

        if let extensionDecl = conformanceExt.as(ExtensionDeclSyntax.self) {
            return [extensionDecl]
        }

        return []
    }
}

/// Error message for @OWLClass macro
struct OWLClassMacroErrorMessage: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(_ message: String) {
        self.message = message
        self.diagnosticID = MessageID(domain: "GraphMacros", id: message)
        self.severity = .error
    }
}
