/// Exact declaration identity over direct Expression edges, without recursive witnesses.
enum ExpressionIdentity {
    static func areEqual(_ lhs: Expression, _ rhs: Expression) -> Bool {
        var left = Cursor(lhs)
        var right = Cursor(rhs)
        while let token = left.next() {
            guard let other = right.next(), token == other else { return false }
        }
        return right.next() == nil
    }

    static func hash(_ expression: Expression, into hasher: inout Hasher) {
        var cursor = Cursor(expression)
        while let token = cursor.next() { hasher.combine(token) }
    }

    private enum Token: Equatable, Hashable {
        case kind(Int)
        case count(Int)
        case bool(Bool)
        case string(String)
        case optionalString(String?)
        case literal(Literal)
        case column(ColumnRef)
        case variable(Variable)
        case parameter(QueryParameterReference)
        case dataType(DataType)
        case query(SelectQuery)
        case direction(SortDirection)
        case nulls(NullOrdering?)
        case current(SQLCurrentValueKind)
        case optionalInt(Int?)
        case pattern(PatternMatchKind)
        case truth(TruthValue)
        case comparison(ComparisonOperator)
        case quantifier(ComparisonQuantifier)
    }

    private enum Step {
        case expression(Expression)
        case optionalExpression(Expression?)
        case expressions([Expression], index: Int)
        case pairs([CaseWhenPair], index: Int)
        case sortKeys([SortKey], index: Int)
        case aggregate(AggregateFunction)
        case token(Token)
    }

    private struct Cursor {
        // Arrays retain COW input owners; one cursor frame per active collection
        // avoids an intermediate flattened tree or workspace proportional to width.
        private var steps: [Step]

        init(_ expression: Expression) {
            steps = [.expression(expression)]
        }

        mutating func next() -> Token? {
            while let step = steps.popLast() {
                switch step {
                case .token(let token): return token
                case .optionalExpression(let value):
                    if let value { steps.append(.expression(value)) }
                    return .bool(value != nil)
                case .expressions(let values, let index):
                    guard index < values.count else { continue }
                    steps.append(.expressions(values, index: index + 1))
                    steps.append(.expression(values[index]))
                case .pairs(let values, let index):
                    guard index < values.count else { continue }
                    steps.append(.pairs(values, index: index + 1))
                    steps.append(.expression(values[index].result))
                    steps.append(.expression(values[index].condition))
                case .sortKeys(let values, let index):
                    guard index < values.count else { continue }
                    let key = values[index]
                    steps.append(.sortKeys(values, index: index + 1))
                    steps.append(.token(.nulls(key.nulls)))
                    steps.append(.token(.direction(key.direction)))
                    steps.append(.expression(key.expression))
                case .aggregate(let value): return enqueue(value)
                case .expression(let value): return enqueue(value)
                }
            }
            return nil
        }

        private mutating func list(_ values: [Expression]) {
            steps.append(.expressions(values, index: 0))
            steps.append(.token(.count(values.count)))
        }

        private mutating func unary(_ value: Expression, kind: Int) -> Token {
            steps.append(.expression(value))
            return .kind(kind)
        }

        private mutating func binary(_ left: Expression, _ right: Expression, kind: Int) -> Token {
            steps.append(.expression(right))
            steps.append(.expression(left))
            return .kind(kind)
        }

        private mutating func enqueue(_ expression: Expression) -> Token {
            switch expression {
            case .currentValue(let kind, let precision):
                steps.append(.token(.optionalInt(precision)))
                steps.append(.token(.current(kind)))
                return .kind(52)
            case .literal(let value):
                steps.append(.token(.literal(value))); return .kind(0)
            case .array(let values): list(values); return .kind(41)
            case .row(let values): list(values); return .kind(42)
            case .column(let value):
                steps.append(.token(.column(value))); return .kind(1)
            case .variable(let value):
                steps.append(.token(.variable(value))); return .kind(2)
            case .parameter(let value):
                steps.append(.token(.parameter(value))); return .kind(40)
            case .add(let l, let r): return binary(l, r, kind: 3)
            case .subtract(let l, let r): return binary(l, r, kind: 4)
            case .multiply(let l, let r): return binary(l, r, kind: 5)
            case .divide(let l, let r): return binary(l, r, kind: 6)
            case .modulo(let l, let r): return binary(l, r, kind: 7)
            case .negate(let value): return unary(value, kind: 8)
            case .equal(let l, let r): return binary(l, r, kind: 9)
            case .notEqual(let l, let r): return binary(l, r, kind: 10)
            case .lessThan(let l, let r): return binary(l, r, kind: 11)
            case .lessThanOrEqual(let l, let r): return binary(l, r, kind: 12)
            case .greaterThan(let l, let r): return binary(l, r, kind: 13)
            case .greaterThanOrEqual(let l, let r): return binary(l, r, kind: 14)
            case .and(let l, let r): return binary(l, r, kind: 15)
            case .or(let l, let r): return binary(l, r, kind: 16)
            case .not(let value): return unary(value, kind: 17)
            case .isNull(let value): return unary(value, kind: 18)
            case .isNotNull(let value): return unary(value, kind: 19)
            case .bound(let value):
                steps.append(.token(.variable(value))); return .kind(20)
            case .patternMatch(let subject, let pattern, let escape, let kind):
                steps.append(.optionalExpression(escape))
                steps.append(.expression(pattern))
                steps.append(.expression(subject))
                steps.append(.token(.pattern(kind)))
                return .kind(50)
            case .concatenate(let lhs, let rhs): return binary(lhs, rhs, kind: 51)
            case .regex(let value, let pattern, let flags):
                steps.append(.token(.optionalString(flags)))
                steps.append(.token(.string(pattern)))
                return unary(value, kind: 22)
            case .between(let value, let low, let high):
                steps.append(.expression(high))
                return binary(value, low, kind: 23)
            case .inList(let value, let values):
                list(values); return unary(value, kind: 24)
            case .notInList(let value, let values):
                list(values); return unary(value, kind: 39)
            case .inSubquery(let value, let query):
                steps.append(.token(.query(query))); return unary(value, kind: 25)
            case .aggregate(let value):
                steps.append(.aggregate(value)); return .kind(26)
            case .function(let value):
                list(value.arguments)
                steps.append(.token(.bool(value.distinct)))
                steps.append(.token(.string(value.name)))
                steps.append(.token(.optionalString(value.schema)))
                return .kind(27)
            case .caseWhen(let operand, let pairs, let fallback):
                steps.append(.optionalExpression(fallback))
                steps.append(.pairs(pairs, index: 0))
                steps.append(.token(.count(pairs.count)))
                steps.append(.optionalExpression(operand))
                return .kind(28)
            case .coalesce(let values): list(values); return .kind(29)
            case .nullIf(let l, let r): return binary(l, r, kind: 30)
            case .cast(let value, let type):
                steps.append(.token(.dataType(type))); return unary(value, kind: 31)
            case .triple(let subject, let predicate, let object):
                steps.append(.expression(object)); return binary(subject, predicate, kind: 32)
            case .isTriple(let value): return unary(value, kind: 33)
            case .subject(let value): return unary(value, kind: 34)
            case .predicate(let value): return unary(value, kind: 35)
            case .object(let value): return unary(value, kind: 36)
            case .subquery(let value):
                steps.append(.token(.query(value))); return .kind(37)
            case .exists(let value):
                steps.append(.token(.query(value))); return .kind(38)
            case .greatest(let values): list(values); return .kind(45)
            case .least(let values): list(values); return .kind(46)
            case .truthTest(let value, let truth, let negated):
                steps.append(.token(.bool(negated)))
                steps.append(.token(.truth(truth)))
                return unary(value, kind: 47)
            case .isDistinctFrom(let left, let right, let negated):
                steps.append(.token(.bool(negated))); return binary(left, right, kind: 48)
            case .quantifiedComparison(let value, let comparison, let quantifier, let source):
                switch source {
                case .array(let value):
                    steps.append(.expression(value)); steps.append(.token(.kind(0)))
                case .subquery(let value):
                    steps.append(.token(.query(value))); steps.append(.token(.kind(1)))
                }
                steps.append(.token(.quantifier(quantifier)))
                steps.append(.token(.comparison(comparison)))
                return unary(value, kind: 49)
            }
        }

        private mutating func enqueue(_ aggregate: AggregateFunction) -> Token {
            switch aggregate {
            case .count(let value, let distinct):
                steps.append(.token(.bool(distinct)))
                steps.append(.optionalExpression(value))
                return .kind(0)
            case .sum(let value, let distinct):
                steps.append(.token(.bool(distinct))); return unary(value, kind: 1)
            case .avg(let value, let distinct):
                steps.append(.token(.bool(distinct))); return unary(value, kind: 2)
            case .min(let value): return unary(value, kind: 3)
            case .max(let value): return unary(value, kind: 4)
            case .groupConcat(let value, let separator, let distinct):
                steps.append(.token(.bool(distinct)))
                steps.append(.token(.optionalString(separator)))
                return unary(value, kind: 5)
            case .sample(let value): return unary(value, kind: 6)
            case .arrayAgg(let value, let orderBy, let distinct):
                steps.append(.token(.bool(distinct)))
                if let orderBy {
                    steps.append(.sortKeys(orderBy, index: 0))
                    steps.append(.token(.count(orderBy.count)))
                }
                steps.append(.token(.bool(orderBy != nil)))
                return unary(value, kind: 7)
            }
        }
    }
}
