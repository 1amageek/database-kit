public struct DatabaseObjectField: Sendable, Hashable {
    public let number: UInt32
    public let name: String
    public let value: DatabaseValue

    public init(number: UInt32, name: String, value: DatabaseValue) {
        self.number = number
        self.name = name
        self.value = value
    }
}
