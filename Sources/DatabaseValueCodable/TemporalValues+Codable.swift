import DatabaseTypes

extension CivilDate: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case year
        case month
        case day
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            year: container.decode(Int32.self, forKey: .year),
            month: container.decode(UInt8.self, forKey: .month),
            day: container.decode(UInt8.self, forKey: .day)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(year, forKey: .year)
        try container.encode(month, forKey: .month)
        try container.encode(day, forKey: .day)
    }
}

extension CivilTime: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case hour
        case minute
        case second
        case nanoseconds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            hour: container.decode(UInt8.self, forKey: .hour),
            minute: container.decode(UInt8.self, forKey: .minute),
            second: container.decode(UInt8.self, forKey: .second),
            nanoseconds: container.decode(UInt32.self, forKey: .nanoseconds)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hour, forKey: .hour)
        try container.encode(minute, forKey: .minute)
        try container.encode(second, forKey: .second)
        try container.encode(nanoseconds, forKey: .nanoseconds)
    }
}

extension CivilDateTime: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case date
        case time
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            date: try container.decode(CivilDate.self, forKey: .date),
            time: try container.decode(CivilTime.self, forKey: .time)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(time, forKey: .time)
    }
}

extension Timestamp: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case seconds
        case nanoseconds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            secondsSinceUnixEpoch: container.decode(
                Int64.self,
                forKey: .seconds
            ),
            nanoseconds: container.decode(
                UInt32.self,
                forKey: .nanoseconds
            )
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(secondsSinceUnixEpoch, forKey: .seconds)
        try container.encode(nanoseconds, forKey: .nanoseconds)
    }
}

extension TimeSpan: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case seconds
        case nanoseconds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            seconds: container.decode(Int64.self, forKey: .seconds),
            nanoseconds: container.decode(
                UInt32.self,
                forKey: .nanoseconds
            )
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seconds, forKey: .seconds)
        try container.encode(nanoseconds, forKey: .nanoseconds)
    }
}

extension CalendarPeriod: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case months
        case days
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            months: try container.decode(Int64.self, forKey: .months),
            days: try container.decode(Int64.self, forKey: .days)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(months, forKey: .months)
        try container.encode(days, forKey: .days)
    }
}
