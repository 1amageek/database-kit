import SwiftSyntax

// MARK: - @OWLDataProperty / @OWLProperty helpers

/// Check if a VariableDecl has @OWLDataProperty or @OWLProperty attribute
public func hasOWLDataPropertyAttribute(_ varDecl: VariableDeclSyntax) -> Bool {
    for attribute in varDecl.attributes {
        if let attr = attribute.as(AttributeSyntax.self),
           let identifier = attr.attributeName.as(IdentifierTypeSyntax.self),
           identifier.name.text == "OWLDataProperty" || identifier.name.text == "OWLProperty" {
            return true
        }
    }
    return false
}

/// Get @OWLDataProperty or @OWLProperty attribute from a VariableDecl
public func getOWLDataPropertyAttribute(_ varDecl: VariableDeclSyntax) -> AttributeSyntax? {
    for attribute in varDecl.attributes {
        if let attr = attribute.as(AttributeSyntax.self),
           let identifier = attr.attributeName.as(IdentifierTypeSyntax.self),
           identifier.name.text == "OWLDataProperty" || identifier.name.text == "OWLProperty" {
            return attr
        }
    }
    return nil
}

/// Extract metadata from @OWLDataProperty / @OWLProperty attribute
///
/// - Returns: (iri, label, targetTypeName, targetFieldName) tuple
///   - iri: OWL property IRI (string literal)
///   - label: Display label (optional)
///   - targetTypeName: Root type name from `to:` parameter (nil for DataProperty)
///   - targetFieldName: Field name from `to:` parameter (nil for DataProperty)
public func extractOWLDataPropertyInfo(from attribute: AttributeSyntax) -> (
    iri: String,
    label: String?,
    targetTypeName: String?,
    targetFieldName: String?
) {
    var iri = ""
    var label: String? = nil
    var targetTypeName: String? = nil
    var targetFieldName: String? = nil

    guard let arguments = attribute.arguments,
          let labeledList = arguments.as(LabeledExprListSyntax.self) else {
        return (iri, label, targetTypeName, targetFieldName)
    }

    for (index, argument) in labeledList.enumerated() {
        let argLabel = argument.label?.text

        if index == 0 && argLabel == nil {
            // First unlabeled argument = IRI string
            let expr = argument.expression.description.trimmingCharacters(in: .whitespaces)
            if expr.hasPrefix("\"") && expr.hasSuffix("\"") {
                iri = String(expr.dropFirst().dropLast())
            } else {
                iri = expr
            }
        } else if argLabel == "label" {
            let expr = argument.expression.description.trimmingCharacters(in: .whitespaces)
            if expr.hasPrefix("\"") && expr.hasSuffix("\"") {
                label = String(expr.dropFirst().dropLast())
            }
        } else if argLabel == "to" {
            // Parse KeyPath expression: \Department.id → (Department, id)
            let expr = argument.expression.description.trimmingCharacters(in: .whitespaces)
            let parsed = parseKeyPathExpression(expr)
            targetTypeName = parsed.rootType
            targetFieldName = parsed.fieldName
        }
    }

    return (iri, label, targetTypeName, targetFieldName)
}

/// Extract Root type name and field name from a KeyPath expression string (`\Department.id`)
///
/// - Parameter expr: String representation of a KeyPath expression
/// - Returns: (rootType, fieldName) tuple
private func parseKeyPathExpression(_ expr: String) -> (rootType: String?, fieldName: String?) {
    var s = expr
    if s.hasPrefix("\\") {
        s = String(s.dropFirst())
    }
    guard let dotIndex = s.firstIndex(of: ".") else {
        return (nil, nil)
    }
    let rootType = String(s[s.startIndex..<dotIndex])
    let fieldName = String(s[s.index(after: dotIndex)...])
    return (rootType.isEmpty ? nil : rootType, fieldName.isEmpty ? nil : fieldName)
}

// MARK: - @OWLObjectProperty helpers

/// Check if a struct has @OWLObjectProperty attribute
public func getOWLObjectPropertyAttribute(_ decl: StructDeclSyntax) -> AttributeSyntax? {
    for attribute in decl.attributes {
        if let attr = attribute.as(AttributeSyntax.self),
           let identifier = attr.attributeName.as(IdentifierTypeSyntax.self),
           identifier.name.text == "OWLObjectProperty" {
            return attr
        }
    }
    return nil
}

/// Extract metadata from @OWLObjectProperty attribute
///
/// - Returns: (iri, fromField, toField) tuple
public func extractOWLObjectPropertyInfo(from attribute: AttributeSyntax) -> (
    iri: String,
    fromField: String,
    toField: String
) {
    var iri = ""
    var fromField = ""
    var toField = ""

    guard let arguments = attribute.arguments,
          let labeledList = arguments.as(LabeledExprListSyntax.self) else {
        return (iri, fromField, toField)
    }

    for (index, argument) in labeledList.enumerated() {
        let argLabel = argument.label?.text

        if index == 0 && argLabel == nil {
            let expr = argument.expression.description.trimmingCharacters(in: .whitespaces)
            if expr.hasPrefix("\"") && expr.hasSuffix("\"") {
                iri = String(expr.dropFirst().dropLast())
            }
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

    return (iri, fromField, toField)
}

