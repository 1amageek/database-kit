/// A failure to construct a valid index declaration.
public struct IndexDeclarationError:
  Error,
  Sendable,
  Equatable,
  CustomStringConvertible
{
  public let indexName: String
  public let validationError: IndexValidationError

  public init(
    indexName: String,
    validationError: IndexValidationError
  ) {
    self.indexName = indexName
    self.validationError = validationError
  }

  public var description: String {
    "Index '\(indexName)' is invalid: \(validationError.description)"
  }
}
