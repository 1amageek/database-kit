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
        case (.int8(let left), .int8(let right)):
            return left < right
        case (.int16(let left), .int16(let right)):
            return left < right
        case (.int32(let left), .int32(let right)):
            return left < right
        case (.int64(let left), .int64(let right)):
            return left < right
        case (.uint8(let left), .uint8(let right)):
            return left < right
        case (.uint16(let left), .uint16(let right)):
            return left < right
        case (.uint32(let left), .uint32(let right)):
            return left < right
        case (.uint64(let left), .uint64(let right)):
            return left < right
        case (.float32(let left), .float32(let right)):
            return left.isTotallyOrdered(belowOrEqualTo: right)
                && left.bitPattern != right.bitPattern
        case (.float64(let left), .float64(let right)):
            return left.isTotallyOrdered(belowOrEqualTo: right)
                && left.bitPattern != right.bitPattern
        case (
            .decimal(let leftCoefficient, let leftScale),
            .decimal(let rightCoefficient, let rightScale)
        ):
            let numericComparison = DatabaseExactDecimal(
                coefficient: leftCoefficient,
                scale: leftScale
            ).compare(
                to: DatabaseExactDecimal(
                    coefficient: rightCoefficient,
                    scale: rightScale
                )
            )
            if numericComparison != 0 {
                return numericComparison < 0
            }
            if leftCoefficient != rightCoefficient {
                return leftCoefficient < rightCoefficient
            }
            return leftScale < rightScale
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
        case .int8: return 2
        case .int16: return 3
        case .int32: return 4
        case .int64: return 5
        case .uint8: return 6
        case .uint16: return 7
        case .uint32: return 8
        case .uint64: return 9
        case .float32: return 10
        case .float64: return 11
        case .decimal: return 12
        case .string: return 13
        case .bytes: return 14
        case .date: return 15
        case .timestamp: return 16
        case .uuid: return 17
        case .array: return 18
        case .object: return 19
        case .reference: return 20
        case .rdfTerm: return 21
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
        case (.int8(let lhs), .int8(let rhs)):
            return lhs < rhs
        case (.int16(let lhs), .int16(let rhs)):
            return lhs < rhs
        case (.int32(let lhs), .int32(let rhs)):
            return lhs < rhs
        case (.int64(let lhs), .int64(let rhs)):
            return lhs < rhs
        case (.uint8(let lhs), .uint8(let rhs)):
            return lhs < rhs
        case (.uint16(let lhs), .uint16(let rhs)):
            return lhs < rhs
        case (.uint32(let lhs), .uint32(let rhs)):
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
        case .int8: return 1
        case .int16: return 2
        case .int32: return 3
        case .int64: return 4
        case .uint8: return 5
        case .uint16: return 6
        case .uint32: return 7
        case .uint64: return 8
        case .string: return 9
        case .bytes: return 10
        case .uuid: return 11
        case .composite: return 12
        }
    }
}
