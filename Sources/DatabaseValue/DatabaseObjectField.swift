public struct DatabaseObjectField: Sendable {
    public let number: UInt32
    public let name: String
    public let value: FieldValue

    public init(number: UInt32, name: String, value: FieldValue) {
        self.number = number
        self.name = name
        self.value = value
    }
}
