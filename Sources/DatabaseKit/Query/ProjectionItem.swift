/// One ordered SELECT or RETURNING target.
public enum ProjectionItem: Sendable, Hashable {
    case expression(Expression, alias: String? = nil)
    case wildcard(qualifier: String? = nil)

    public init(_ expression: Expression, alias: String? = nil) {
        self = .expression(expression, alias: alias)
    }

    public static func column(_ name: String) -> ProjectionItem {
        .expression(.col(name))
    }

    public static func column(_ name: String, as alias: String) -> ProjectionItem {
        .expression(.col(name), alias: alias)
    }
}
