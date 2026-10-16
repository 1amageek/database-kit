enum QueryValueAccounting {
    static func add(_ lhs: UInt64, _ rhs: UInt64) throws(QueryValueError) -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw .arithmeticOverflow }
        return result.partialValue
    }

    static func multiply(_ lhs: UInt64, _ rhs: UInt64) throws(QueryValueError) -> UInt64 {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else { throw .arithmeticOverflow }
        return result.partialValue
    }

    static func check(_ actual: UInt64, _ maximum: UInt64, _ resource: String) throws(QueryValueError) {
        guard actual <= maximum else { throw .resourceLimit(resource: resource, actual: actual, maximum: maximum) }
    }

    static func slots(_ count: Int, stride: Int) throws(QueryValueError) -> UInt64 {
        guard count >= 0 else { throw .invalidValueConstruction }
        return try multiply(UInt64(count), UInt64(stride))
    }

    static func integer(_ count: UInt64) throws(QueryValueError) -> Int {
        guard let result = Int(exactly: count) else { throw .arithmeticOverflow }
        return result
    }
}
