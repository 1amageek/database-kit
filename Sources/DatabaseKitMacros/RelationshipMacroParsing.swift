import SwiftSyntax

struct ParsedRelationshipField {
    let relatedTypeName: String
    let cardinalityExpression: String
}

func parseRelationshipField(_ type: TypeSyntax) -> ParsedRelationshipField? {
    if let target = databaseReferenceTarget(from: type) {
        return ParsedRelationshipField(
            relatedTypeName: target.trimmedDescription,
            cardinalityExpression: ".requiredToOne"
        )
    }

    if let optional = optionalWrappedType(from: type),
       let target = databaseReferenceTarget(from: optional) {
        return ParsedRelationshipField(
            relatedTypeName: target.trimmedDescription,
            cardinalityExpression: ".optionalToOne"
        )
    }

    if let element = arrayElementType(from: type),
       let target = databaseReferenceTarget(from: element) {
        return ParsedRelationshipField(
            relatedTypeName: target.trimmedDescription,
            cardinalityExpression: ".toMany"
        )
    }

    return nil
}

func extractRelationshipDeleteRule(from attribute: AttributeSyntax) -> String {
    guard let arguments = attribute.arguments,
          let labeledList = arguments.as(LabeledExprListSyntax.self) else {
        return ".nullify"
    }

    for argument in labeledList where argument.label?.text == "deleteRule" {
        return argument.expression.trimmedDescription
    }
    return ".nullify"
}

func hasRelationshipAttribute(_ declaration: VariableDeclSyntax) -> Bool {
    getRelationshipAttribute(declaration) != nil
}

func getRelationshipAttribute(_ declaration: VariableDeclSyntax) -> AttributeSyntax? {
    for element in declaration.attributes {
        guard let attribute = element.as(AttributeSyntax.self) else { continue }
        if attribute.attributeName.trimmedDescription == "Relationship" {
            return attribute
        }
    }
    return nil
}

private func databaseReferenceTarget(from type: TypeSyntax) -> TypeSyntax? {
    genericArgument(from: type, named: "PersistableReference")
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
