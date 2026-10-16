import DatabaseKit

/// Closed temporal discriminator productions shared by eager and lazy codecs.
enum SQLTemporalWireCodec {
    static func encode(_ value: SQLIntervalFields) -> UInt8 {
        switch value {
        case .year: return 0
        case .month: return 1
        case .day: return 2
        case .hour: return 3
        case .minute: return 4
        case .second: return 5
        case .yearToMonth: return 6
        case .dayToHour: return 7
        case .dayToMinute: return 8
        case .dayToSecond: return 9
        case .hourToMinute: return 10
        case .hourToSecond: return 11
        case .minuteToSecond: return 12
        }
    }

    static func intervalFields(_ tag: UInt8) throws(DatabaseWireError) -> SQLIntervalFields {
        switch tag {
        case 0: return .year
        case 1: return .month
        case 2: return .day
        case 3: return .hour
        case 4: return .minute
        case 5: return .second
        case 6: return .yearToMonth
        case 7: return .dayToHour
        case 8: return .dayToMinute
        case 9: return .dayToSecond
        case 10: return .hourToMinute
        case 11: return .hourToSecond
        case 12: return .minuteToSecond
        default: throw .invalidValueTag(tag)
        }
    }

    static func encode(_ value: SQLCurrentValueKind) -> UInt8 {
        switch value {
        case .date: return 0
        case .time: return 1
        case .timestamp: return 2
        case .localTime: return 3
        case .localTimestamp: return 4
        }
    }

    static func currentKind(_ tag: UInt8) throws(DatabaseWireError) -> SQLCurrentValueKind {
        switch tag {
        case 0: return .date
        case 1: return .time
        case 2: return .timestamp
        case 3: return .localTime
        case 4: return .localTimestamp
        default: throw .invalidValueTag(tag)
        }
    }

    static func encode(_ value: QueryTemporalInfinity) -> UInt8 {
        switch value { case .negative: return 0; case .positive: return 1 }
    }

    static func infinity(_ tag: UInt8) throws(DatabaseWireError) -> QueryTemporalInfinity {
        switch tag {
        case 0: return .negative
        case 1: return .positive
        default: throw .invalidValueTag(tag)
        }
    }
}
