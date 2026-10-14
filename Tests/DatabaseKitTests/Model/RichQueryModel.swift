import DatabaseKit
import DatabaseTypes

@Persistable
struct RichQueryModel {
    var id: String
    var numeric: QueryNumericValue
    var json: QueryJSONValue
    var jsonb: QueryJSONBValue
    var interval: QueryIntervalValue
    var matrix: QueryArray<Int32>
    var optionalJSON: QueryJSONValue?
}
