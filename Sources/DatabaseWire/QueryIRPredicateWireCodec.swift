import DatabaseKit

/// Closed discriminator mappings for SQL predicates in canonical QueryIR.
enum QueryIRPredicateWireCodec {
    static func tag(_ value: TruthValue) -> UInt8 {
        switch value { case .false: return 0; case .true: return 1; case .unknown: return 2 }
    }

    static func tag(_ value: ComparisonOperator) -> UInt8 {
        switch value {
        case .equal: return 0
        case .notEqual: return 1
        case .lessThan: return 2
        case .lessThanOrEqual: return 3
        case .greaterThan: return 4
        case .greaterThanOrEqual: return 5
        }
    }

    static func tag(_ value: ComparisonQuantifier) -> UInt8 {
        switch value { case .any: return 0; case .all: return 1 }
    }

    static func truth(_ tag: UInt8) throws(DatabaseWireError) -> TruthValue {
        switch tag {
        case 0: return .false
        case 1: return .true
        case 2: return .unknown
        default: throw .invalidValueTag(tag)
        }
    }

    static func comparison(_ tag: UInt8) throws(DatabaseWireError) -> ComparisonOperator {
        switch tag {
        case 0: return .equal
        case 1: return .notEqual
        case 2: return .lessThan
        case 3: return .lessThanOrEqual
        case 4: return .greaterThan
        case 5: return .greaterThanOrEqual
        default: throw .invalidValueTag(tag)
        }
    }

    static func quantifier(_ tag: UInt8) throws(DatabaseWireError) -> ComparisonQuantifier {
        switch tag { case 0: return .any; case 1: return .all; default: throw .invalidValueTag(tag) }
    }
}
