import SwiftSyntax

// MARK: - @OWLProperty マクロヘルパー

/// VariableDecl に @OWLProperty 属性があるかを判定
public func hasPropertyAttribute(_ varDecl: VariableDeclSyntax) -> Bool {
    for attribute in varDecl.attributes {
        if let attr = attribute.as(AttributeSyntax.self),
           let identifier = attr.attributeName.as(IdentifierTypeSyntax.self),
           identifier.name.text == "OWLProperty" {
            return true
        }
    }
    return false
}

/// VariableDecl から @OWLProperty 属性を取得
public func getPropertyAttribute(_ varDecl: VariableDeclSyntax) -> AttributeSyntax? {
    for attribute in varDecl.attributes {
        if let attr = attribute.as(AttributeSyntax.self),
           let identifier = attr.attributeName.as(IdentifierTypeSyntax.self),
           identifier.name.text == "OWLProperty" {
            return attr
        }
    }
    return nil
}

/// @OWLProperty 属性からメタデータを抽出
///
/// - Returns: (iri, label, targetTypeName, targetFieldName) タプル
///   - iri: OWL プロパティ IRI（文字列リテラル）
///   - label: 表示ラベル（nil 可）
///   - targetTypeName: `to:` パラメータの Root 型名（nil なら DataProperty）
///   - targetFieldName: `to:` パラメータのフィールド名（nil なら DataProperty）
public func extractPropertyInfo(from attribute: AttributeSyntax) -> (
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
            // 最初の無名引数 = IRI 文字列
            let expr = argument.expression.description.trimmingCharacters(in: .whitespaces)
            // クォーテーションを除去
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
            // KeyPath 式をパース: \Department.id → (Department, id)
            let expr = argument.expression.description.trimmingCharacters(in: .whitespaces)
            let parsed = parseKeyPathExpression(expr)
            targetTypeName = parsed.rootType
            targetFieldName = parsed.fieldName
        }
    }

    return (iri, label, targetTypeName, targetFieldName)
}

/// KeyPath 式文字列 (`\Department.id`) から Root 型名とフィールド名を抽出
///
/// - Parameter expr: KeyPath 式の文字列表現
/// - Returns: (rootType, fieldName) タプル
private func parseKeyPathExpression(_ expr: String) -> (rootType: String?, fieldName: String?) {
    // パターン: \TypeName.fieldName
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
