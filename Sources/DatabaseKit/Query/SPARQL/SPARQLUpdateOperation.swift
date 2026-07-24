/// One operation in a SPARQL Update request.
///
/// Query forms and nested update requests are intentionally absent, making a
/// mixed or recursive request unrepresentable.
public enum SPARQLUpdateOperation: Sendable, Equatable, Hashable {
    case insertData(InsertDataQuery)
    case deleteData(DeleteDataQuery)
    case modify(SPARQLModifyOperation)
    case deleteWhere(DeleteWhereQuery)
    case load(LoadQuery)
    case clear(ClearQuery)
    case createGraph(CreateSPARQLGraphQuery)
    case drop(DropQuery)
    case graphTransfer(GraphTransferQuery)
}
