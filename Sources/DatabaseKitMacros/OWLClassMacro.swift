import Foundation
import DatabaseTypes
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
                        "@OWLClass requires a class IRI and an individualIRIBase"
                    )
                )
            ])
        }

        guard let rawIRI = Self.plainStringLiteral(firstArg.expression) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(firstArg),
                    message: OWLClassMacroErrorMessage(
                        "@OWLClass class IRI must be a plain string literal"
                    )
                )
            ])
        }
        guard RDFIRISyntax.isValid(rawIRI) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(firstArg),
                    message: OWLClassMacroErrorMessage(
                        "@OWLClass class IRI must be absolute"
                    )
                )
            ])
        }

        var individualIRIBase: String?
        var graphIRI: String?
        for arg in labeledList.dropFirst() {
            switch arg.label?.text {
            case "individualIRIBase":
                guard let value = Self.plainStringLiteral(arg.expression) else {
                    throw DiagnosticsError(diagnostics: [
                        Diagnostic(
                            node: Syntax(arg),
                            message: OWLClassMacroErrorMessage(
                                "@OWLClass 'individualIRIBase:' must be a string literal"
                            )
                        )
                    ])
                }
                individualIRIBase = value
            case "graph":
                let expression = arg.expression.description
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if expression == "nil" {
                    graphIRI = nil
                    continue
                }
                guard let value = Self.plainStringLiteral(arg.expression) else {
                    throw DiagnosticsError(diagnostics: [
                        Diagnostic(
                            node: Syntax(arg),
                            message: OWLClassMacroErrorMessage(
                                "@OWLClass 'graph:' must be a string literal or nil"
                            )
                        )
                    ])
                }
                graphIRI = value
            default:
                continue
            }
        }

        guard let individualIRIBase else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OWLClassMacroErrorMessage(
                        "@OWLClass requires an explicit individualIRIBase"
                    )
                )
            ])
        }

        guard !individualIRIBase.isEmpty else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OWLClassMacroErrorMessage(
                        "@OWLClass 'individualIRIBase:' must not be empty"
                    )
                )
            ])
        }
        guard RDFIRISyntax.isValid(individualIRIBase) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OWLClassMacroErrorMessage(
                        "@OWLClass 'individualIRIBase:' must be an absolute IRI"
                    )
                )
            ])
        }

        if let graphIRI, graphIRI.isEmpty {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OWLClassMacroErrorMessage(
                        "@OWLClass 'graph:' must not be empty"
                    )
                )
            ])
        }
        if let graphIRI, !RDFIRISyntax.isValid(graphIRI) {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OWLClassMacroErrorMessage(
                        "@OWLClass 'graph:' must be an absolute IRI"
                    )
                )
            ])
        }

        let structName = structDecl.name.text

        // Collect @OWLDataProperty annotated fields.
        var ontologyProperties: [(fieldName: String, iri: String, label: String?, targetTypeName: String?, targetFieldName: String?)] = []

        for member in structDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                guard let propertyAttr = getOWLDataPropertyAttribute(varDecl) else { continue }
                let info = extractOWLDataPropertyInfo(from: propertyAttr)
                guard RDFIRISyntax.isValid(info.iri) else {
                    throw DiagnosticsError(diagnostics: [
                        Diagnostic(
                            node: Syntax(propertyAttr),
                            message: OWLClassMacroErrorMessage(
                                "@OWLDataProperty IRI must be absolute"
                            )
                        )
                    ])
                }
                if info.targetTypeName != nil, info.targetFieldName != "id" {
                    throw DiagnosticsError(diagnostics: [
                        Diagnostic(
                            node: Syntax(propertyAttr),
                            message: OWLClassMacroErrorMessage(
                                "OWL object properties must reference the target id field"
                            )
                        )
                    ])
                }

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

        // Generate ontologyClassIRI
        let ontologyClassDecl: DeclSyntax = """
            public static var ontologyClassIRI: String { "\(raw: rawIRI)" }
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

        let individualIRIBaseDecl: DeclSyntax = """
            public static var ontologyIndividualIRIBase: String { "\(raw: individualIRIBase)" }
            """
        decls.append(individualIRIBaseDecl)

        let ontologyGraphBody = graphIRI.map {
            """
            do {
                        return RDFGraphName(
                            RDFSubject.iri(try RDFIRI("\($0)"))
                        )
                    } catch {
                        preconditionFailure("The macro emitted an invalid ontology graph IRI")
                    }
            """
        } ?? "return nil"
        let ontologyGraphDecl: DeclSyntax = """
            public static var ontologyGraph: RDFGraphName? {
                \(raw: ontologyGraphBody)
            }
            """
        decls.append(ontologyGraphDecl)

        let subjectDecl: DeclSyntax = """
            public func ontologySubject() throws(OWLProjectionError) -> RDFSubject {
                try OWLIndividualIRIBuilder.subject(
                    baseIRI: Self.ontologyIndividualIRIBase,
                    persistableType: Self.persistableType,
                    identifier: self.id
                )
            }
            """
        decls.append(subjectDecl)

        var projectionStatements: [String] = []
        for (propertyIndex, property) in ontologyProperties.enumerated() {
            let objectsExpression: String
            if let targetTypeName = property.targetTypeName {
                objectsExpression = """
                try OWLIndividualIRIBuilder.terms(
                                baseIRI: Self.ontologyIndividualIRIBase,
                                persistableType: \(targetTypeName).persistableType,
                                value: self.\(property.fieldName)
                            )
                """
            } else {
                objectsExpression = "try self.\(property.fieldName).owlDataPropertyTerms()"
            }

            projectionStatements.append(
                """
                for object in \(objectsExpression) {
                            let predicate\(propertyIndex): RDFPredicateIRI
                            do {
                                predicate\(propertyIndex) = try RDFPredicateIRI(
                                    "\(property.iri)"
                                )
                            } catch let error {
                                throw .invalidPropertyIRI(
                                    "\(property.iri)",
                                    error
                                )
                            }
                            quads.append(
                                RDFQuad(
                                    subject: subject,
                                    predicate: predicate\(propertyIndex),
                                    object: object,
                                    graph: Self.ontologyGraph
                                )
                            )
                        }
                """
            )
        }

        let projectionBody = projectionStatements.joined(separator: "\n        ")
        let quadsBinding = ontologyProperties.isEmpty ? "let" : "var"
        let quadsDecl: DeclSyntax = """
            public func ontologyQuads() throws(OWLProjectionError) -> [RDFQuad] {
                let subject = try ontologySubject()
                let rdfType: RDFPredicateIRI
                do {
                    rdfType = try OWLRDFVocabulary.rdfType
                } catch let error {
                    throw .invalidVocabularyIRI(
                        "http://www.w3.org/1999/02/22-rdf-syntax-ns#type",
                        error
                    )
                }
                let classTerm: RDFTerm
                do {
                    classTerm = try .iri(
                        validating: Self.ontologyClassIRI
                    )
                } catch let error {
                    throw .invalidClassIRI(
                        Self.ontologyClassIRI,
                        error
                    )
                }
                \(raw: quadsBinding) quads = [
                    RDFQuad(
                        subject: subject,
                        predicate: rdfType,
                        object: classTerm,
                        graph: Self.ontologyGraph
                    )
                ]
                \(raw: projectionBody)
                return quads
            }
            """
        decls.append(quadsDecl)

        let owlRDFDecl: DeclSyntax = """
            public static var _owlRDFIndexDescriptors: [IndexDescriptor] {
                get throws(IndexDeclarationError) {
                    try [IndexDescriptor(name: \(raw: structName).persistableType + "_owl_rdf", kind: OWLClassRDFIndexKind<\(raw: structName)>(individualIRIBase: "\(raw: individualIRIBase)", graph: Self.ontologyGraph))]
                }
            }
            """
        decls.append(owlRDFDecl)

        return decls
    }

    // MARK: - IRI Resolution

    private static func plainStringLiteral(_ expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self),
              literal.segments.count == 1,
              let segment = literal.segments.first?.as(StringSegmentSyntax.self),
              !segment.content.text.contains("\\") else {
            return nil
        }
        return segment.content.text
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
        self.diagnosticID = MessageID(domain: "OntologyDeclaration", id: message)
        self.severity = .error
    }
}
