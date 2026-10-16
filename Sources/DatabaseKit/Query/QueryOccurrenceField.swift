/// Source-independent semantic child roles within QueryIR.
public enum QueryOccurrenceField: Sendable, Equatable, Hashable {
    case statement
    case cte
    case projection
    case source
    case filter
    case groupBy
    case having
    case distinctOn
    case offset
    case limit
    case setLeft
    case setRight
    case valuesRow
    case valuesCell
    case orderBy
    case joinLeft
    case joinRight
    case joinCondition
    case subquery
    case left
    case right
    case operand
    case argument
    case caseCondition
    case caseResult
    case caseElse
    case castType
    case aggregateArgument
    case aggregateOrderBy
    case elementType
}
