import SwiftSyntax

final class KeyPathCollector: SyntaxVisitor {
    private(set) var fieldPaths: [String] = []

    override func visit(_ node: KeyPathExprSyntax) -> SyntaxVisitorContinueKind {
        let fieldPath = node.components.compactMap { component in
            component.component
                .as(KeyPathPropertyComponentSyntax.self)?
                .declName
                .baseName
                .text
        }
        .joined(separator: ".")

        if !fieldPath.isEmpty {
            fieldPaths.append(fieldPath)
        }
        return .skipChildren
    }

    override func visit(
        _ node: MemberAccessExprSyntax
    ) -> SyntaxVisitorContinueKind {
        if
            let namespace = node.base?.as(MemberAccessExprSyntax.self),
            namespace.declName.baseName.text == "fields"
        {
            fieldPaths.append(node.declName.baseName.text)
        }
        return .visitChildren
    }
}

func collectKeyPathStrings(from expression: ExprSyntax) -> [String] {
    let collector = KeyPathCollector(viewMode: .sourceAccurate)
    collector.walk(expression)
    var seen: Set<String> = []
    return collector.fieldPaths.filter { seen.insert($0).inserted }
}
