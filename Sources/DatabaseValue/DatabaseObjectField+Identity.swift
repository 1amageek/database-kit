extension DatabaseObjectField: Hashable {
    public static func == (
        left: DatabaseObjectField,
        right: DatabaseObjectField
    ) -> Bool {
        left.number == right.number
            && DatabaseStringIdentity.equal(left.name, right.name)
            && left.value == right.value
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(number)
        DatabaseStringIdentity.hash(name, into: &hasher)
        hasher.combine(value)
    }
}
