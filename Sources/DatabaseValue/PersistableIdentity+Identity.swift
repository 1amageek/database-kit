extension PersistableIdentity: Hashable {
    public static func == (
        left: PersistableIdentity,
        right: PersistableIdentity
    ) -> Bool {
        DatabaseStringIdentity.equal(left.entity, right.entity)
            && left.id == right.id
            && left.partitions == right.partitions
    }

    public func hash(into hasher: inout Hasher) {
        DatabaseStringIdentity.hash(entity, into: &hasher)
        hasher.combine(id)
        hasher.combine(partitions)
    }
}
