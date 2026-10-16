enum QueryValueIdentity {
    private enum PairVisit {
        case values(QueryValue, QueryValue)
        case children(QueryValueElements, QueryValueElements, Int)
    }

    static func areEqual(_ lhs: QueryValue, _ rhs: QueryValue) -> Bool {
        var work: [PairVisit] = [.values(lhs, rhs)]
        while let visit = work.popLast() {
            switch visit {
            case .children(let a, let b, let i):
                if i + 1 < a.count { work.append(.children(a, b, i + 1)) }
                work.append(.values(a[i], b[i]))
            case .values(let a, let b):
                switch (a, b) {
                case (.array(let a), .array(let b)):
                    guard a.elementType == b.elementType, a.dimensions.elementsEqual(b.dimensions),
                          a.elements.count == b.elements.count else { return false }
                    if !a.elements.isEmpty { work.append(.children(a.elements, b.elements, 0)) }
                case (.composite(let a), .composite(let b)):
                    guard a.type == b.type, a.fields.count == b.fields.count else { return false }
                    if !a.fields.isEmpty { work.append(.children(a.fields, b.fields, 0)) }
                case (.primitive(let a), .primitive(let b)): if a != b { return false }
                case (.numeric(let a), .numeric(let b)): if a != b { return false }
                case (.json(let a), .json(let b)): if a != b { return false }
                case (.jsonb(let a), .jsonb(let b)): if a != b { return false }
                case (.interval(let a), .interval(let b)): if a != b { return false }
                case (.time(let a), .time(let b)): if a != b { return false }
                case (.timeWithTimeZone(let a), .timeWithTimeZone(let b)): if a != b { return false }
                case (.dateInfinity(let a), .dateInfinity(let b)): if a != b { return false }
                case (.timestampInfinity(let a, let x), .timestampInfinity(let b, let y)):
                    if a != b || x != y { return false }
                case (.intervalInfinity(let a), .intervalInfinity(let b)): if a != b { return false }
                default: return false
                }
            }
        }
        return true
    }

    private enum HashVisit {
        case value(QueryValue)
        case children(QueryValueElements, Int)
    }

    static func hash(_ value: QueryValue, into hasher: inout Hasher) {
        var work: [HashVisit] = [.value(value)]
        while let visit = work.popLast() {
            switch visit {
            case .children(let values, let i):
                if i + 1 < values.count { work.append(.children(values, i + 1)) }
                work.append(.value(values[i]))
            case .value(let value):
                switch value {
                case .primitive(let x): hasher.combine(0); hasher.combine(x)
                case .numeric(let x): hasher.combine(1); hasher.combine(x)
                case .json(let x): hasher.combine(2); hasher.combine(x)
                case .jsonb(let x): hasher.combine(3); hasher.combine(x)
                case .array(let x):
                    hasher.combine(4); hasher.combine(x.elementType)
                    hasher.combine(x.dimensions.count)
                    for dimension in x.dimensions { hasher.combine(dimension) }
                    hasher.combine(x.elements.count)
                    if !x.elements.isEmpty { work.append(.children(x.elements, 0)) }
                case .interval(let x): hasher.combine(5); hasher.combine(x)
                case .time(let x): hasher.combine(6); hasher.combine(x)
                case .timeWithTimeZone(let x): hasher.combine(7); hasher.combine(x)
                case .dateInfinity(let x): hasher.combine(8); hasher.combine(x)
                case .timestampInfinity(let x, let zone): hasher.combine(9); hasher.combine(x); hasher.combine(zone)
                case .intervalInfinity(let x): hasher.combine(10); hasher.combine(x)
                case .composite(let x):
                    hasher.combine(11); hasher.combine(x.type); hasher.combine(x.fields.count)
                    if !x.fields.isEmpty { work.append(.children(x.fields, 0)) }
                }
            }
        }
    }
}
