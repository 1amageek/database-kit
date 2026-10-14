import DatabaseKit
import DatabaseTypes

@Persistable
struct RichQueryDefaultModel {
    var id: String
    var numeric: QueryNumericValue = try! QueryNumericValue(
        value: ExactDecimal(coefficient: 1, scale: 0),
        displayScale: 2
    )
    var optionalNumeric: QueryNumericValue?
}
