extension FieldValue: Comparable {
    public static func < (lhs: FieldValue, rhs: FieldValue) -> Bool {
        let lhsRank = rank(of: lhs)
        let rhsRank = rank(of: rhs)
        guard lhsRank == rhsRank else {
            return lhsRank < rhsRank
        }

        switch (lhs, rhs) {
        case (.null, .null):
            return false
        case (.bool(let left), .bool(let right)):
            return !left && right
        case (.int64(let left), .int64(let right)):
            return left < right
        case (.uint64(let left), .uint64(let right)):
            return left < right
        case (.double(let left), .double(let right)):
            return left.isTotallyOrdered(belowOrEqualTo: right) && left != right
        case (
            .decimal(let leftCoefficient, let leftScale),
            .decimal(let rightCoefficient, let rightScale)
        ):
            return DatabaseExactDecimal(
                coefficient: leftCoefficient,
                scale: leftScale
            ).compare(
                to: DatabaseExactDecimal(
                    coefficient: rightCoefficient,
                    scale: rightScale
                )
            ) < 0
        case (.string(let left), .string(let right)):
            return DatabaseStringIdentity.less(left, right)
        case (.bytes(let left), .bytes(let right)):
            return left.lexicographicallyPrecedes(right)
        case (.date(let left), .date(let right)):
            return left < right
        case (.timestamp(let left), .timestamp(let right)):
            return left < right
        case (.uuid(let left), .uuid(let right)):
            return left < right
        case (.array(let left), .array(let right)):
            return lexicographicallyPrecedes(left, right)
        case (.object(let left), .object(let right)):
            return objectFieldsPrecede(left, right)
        case (.reference(let left), .reference(let right)):
            return identitiesPrecede(left, right)
        case (.rdfTerm(let left), .rdfTerm(let right)):
            return left < right
        default:
            return false
        }
    }

    private static func rank(of value: FieldValue) -> UInt8 {
        switch value {
        case .null: return 0
        case .bool: return 1
        case .int64: return 2
        case .uint64: return 3
        case .double: return 4
        case .decimal: return 5
        case .string: return 6
        case .bytes: return 7
        case .date: return 8
        case .timestamp: return 9
        case .uuid: return 10
        case .array: return 11
        case .object: return 12
        case .reference: return 13
        case .rdfTerm: return 14
        }
    }

    private static func lexicographicallyPrecedes(
        _ left: [FieldValue],
        _ right: [FieldValue]
    ) -> Bool {
        let sharedCount = min(left.count, right.count)
        for index in 0..<sharedCount {
            if left[index] == right[index] {
                continue
            }
            return left[index] < right[index]
        }
        return left.count < right.count
    }

    private static func objectFieldsPrecede(
        _ left: [DatabaseObjectField],
        _ right: [DatabaseObjectField]
    ) -> Bool {
        let sharedCount = min(left.count, right.count)
        for index in 0..<sharedCount {
            let leftField = left[index]
            let rightField = right[index]
            if leftField.number != rightField.number {
                return leftField.number < rightField.number
            }
            if !DatabaseStringIdentity.equal(leftField.name, rightField.name) {
                return DatabaseStringIdentity.less(
                    leftField.name,
                    rightField.name
                )
            }
            if leftField.value != rightField.value {
                return leftField.value < rightField.value
            }
        }
        return left.count < right.count
    }

    private static func identitiesPrecede(
        _ left: PersistableIdentity,
        _ right: PersistableIdentity
    ) -> Bool {
        if !DatabaseStringIdentity.equal(left.entity, right.entity) {
            return DatabaseStringIdentity.less(left.entity, right.entity)
        }
        if left.id != right.id {
            return identifierPrecedes(left.id, right.id)
        }
        return objectFieldsPrecede(left.partitions, right.partitions)
    }

    private static func identifierPrecedes(
        _ left: PersistableIdentifierValue,
        _ right: PersistableIdentifierValue
    ) -> Bool {
        let leftRank = identifierRank(of: left)
        let rightRank = identifierRank(of: right)
        guard leftRank == rightRank else {
            return leftRank < rightRank
        }
        switch (left, right) {
        case (.bool(let lhs), .bool(let rhs)):
            return !lhs && rhs
        case (.int64(let lhs), .int64(let rhs)):
            return lhs < rhs
        case (.uint64(let lhs), .uint64(let rhs)):
            return lhs < rhs
        case (.string(let lhs), .string(let rhs)):
            return DatabaseStringIdentity.less(lhs, rhs)
        case (.bytes(let lhs), .bytes(let rhs)):
            return lhs.lexicographicallyPrecedes(rhs)
        case (.uuid(let lhs), .uuid(let rhs)):
            return lhs < rhs
        case (.composite(let lhs), .composite(let rhs)):
            let sharedCount = min(lhs.count, rhs.count)
            for index in 0..<sharedCount {
                if lhs[index] == rhs[index] {
                    continue
                }
                return identifierPrecedes(lhs[index], rhs[index])
            }
            return lhs.count < rhs.count
        default:
            return false
        }
    }

    private static func identifierRank(
        of value: PersistableIdentifierValue
    ) -> UInt8 {
        switch value {
        case .bool: return 0
        case .int64: return 1
        case .uint64: return 2
        case .string: return 3
        case .bytes: return 4
        case .uuid: return 5
        case .composite: return 6
        }
    }
}
