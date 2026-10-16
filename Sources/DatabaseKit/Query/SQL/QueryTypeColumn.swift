package struct QueryTypeColumn: Sendable {
    package let number: UInt32
    package let name: String
    package let type: Int
    package let isNullable: Bool

    package init(number: UInt32, name: String, type: Int, isNullable: Bool) {
        self.number = number
        self.name = name
        self.type = type
        self.isNullable = isNullable
    }
}
