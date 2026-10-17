/// Immutable SQL NamedWindow declaration; execution is owned by the SQL runtime.
public struct NamedWindow: Sendable, Hashable {
    public let name: String
    public let specification: WindowSpecification

    public init(name: String, specification: WindowSpecification) {
        self.name = name
        self.specification = specification
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name.utf8.elementsEqual(rhs.name.utf8) && lhs.specification == rhs.specification
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name.utf8.count)
        for byte in name.utf8 { hasher.combine(byte) }
        hasher.combine(specification)
    }
}
