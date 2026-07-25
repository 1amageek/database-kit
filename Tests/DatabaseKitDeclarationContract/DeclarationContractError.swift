import DatabaseKit

enum DeclarationContractError: Error {
    case invalidEntity(SchemaEntityError)
    case invalidSchema(SchemaError)
}
