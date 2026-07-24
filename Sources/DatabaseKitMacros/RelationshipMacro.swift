import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct RelationshipMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self) else {
            throw diagnostic(
                node,
                "@Relationship can only be applied to a stored variable"
            )
        }
        guard variable.bindingSpecifier.text == "var" else {
            throw diagnostic(
                node,
                "@Relationship requires a mutable stored variable"
            )
        }
        guard variable.bindings.count == 1,
              let binding = variable.bindings.first,
              binding.accessorBlock == nil,
              let annotation = binding.typeAnnotation else {
            throw diagnostic(
                node,
                "@Relationship requires one stored variable with an explicit type"
            )
        }
        guard let cardinality = relationshipCardinality(of: annotation.type) else {
            throw diagnostic(
                annotation.type,
                "@Relationship fields must be DatabaseReference<Target>, DatabaseReference<Target>?, or [DatabaseReference<Target>]"
            )
        }

        let deleteRule = try relationshipDeleteRule(from: node)
        if cardinality == .requiredToOne, deleteRule == "nullify" {
            throw diagnostic(
                node,
                "deleteRule .nullify requires an optional to-one or to-many relationship"
            )
        }

        return []
    }
}

private enum ParsedCardinality {
    case requiredToOne
    case optionalToOne
    case toMany
}

private func relationshipCardinality(of type: TypeSyntax) -> ParsedCardinality? {
    if databaseReferenceTarget(from: type) != nil {
        return .requiredToOne
    }
    if let wrapped = optionalWrappedType(from: type),
       databaseReferenceTarget(from: wrapped) != nil {
        return .optionalToOne
    }
    if let element = arrayElementType(from: type),
       databaseReferenceTarget(from: element) != nil {
        return .toMany
    }
    return nil
}

private func relationshipDeleteRule(from attribute: AttributeSyntax) throws -> String {
    guard let arguments = attribute.arguments,
          let labeledList = arguments.as(LabeledExprListSyntax.self) else {
        return "nullify"
    }

    var result = "nullify"
    for argument in labeledList {
        guard argument.label?.text == "deleteRule" else {
            throw diagnostic(
                argument,
                "@Relationship only accepts the deleteRule argument"
            )
        }
        let expression = argument.expression.trimmedDescription
        let value = expression.split(separator: ".").last.map(String.init) ?? expression
        guard ["nullify", "cascade", "deny", "noAction"].contains(value) else {
            throw diagnostic(
                argument.expression,
                "@Relationship deleteRule must be nullify, cascade, deny, or noAction"
            )
        }
        result = value
    }
    return result
}

private func databaseReferenceTarget(from type: TypeSyntax) -> TypeSyntax? {
    genericArgument(from: type, named: "DatabaseReference")
}

private func optionalWrappedType(from type: TypeSyntax) -> TypeSyntax? {
    if let optional = type.as(OptionalTypeSyntax.self) {
        return optional.wrappedType
    }
    return genericArgument(from: type, named: "Optional")
}

private func arrayElementType(from type: TypeSyntax) -> TypeSyntax? {
    if let array = type.as(ArrayTypeSyntax.self) {
        return array.element
    }
    return genericArgument(from: type, named: "Array")
}

private func genericArgument(
    from type: TypeSyntax,
    named expectedName: String
) -> TypeSyntax? {
    if let identifier = type.as(IdentifierTypeSyntax.self),
       identifier.name.text == expectedName,
       let arguments = identifier.genericArgumentClause?.arguments,
       arguments.count == 1,
       let first = arguments.first,
       case .type(let argument) = first.argument {
        return argument
    }
    if let member = type.as(MemberTypeSyntax.self),
       member.name.text == expectedName,
       let arguments = member.genericArgumentClause?.arguments,
       arguments.count == 1,
       let first = arguments.first,
       case .type(let argument) = first.argument {
        return argument
    }
    return nil
}

private func diagnostic(
    _ node: some SyntaxProtocol,
    _ message: String
) -> DiagnosticsError {
    DiagnosticsError(diagnostics: [
        Diagnostic(
            node: Syntax(node),
            message: RelationshipDiagnostic(message)
        )
    ])
}

private struct RelationshipDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity = .error

    init(_ message: String) {
        self.message = message
        self.diagnosticID = MessageID(domain: "RelationshipDeclaration", id: message)
    }
}
