/// A concrete destination for fields emitted by macro-generated model traversal.
///
/// The generic value parameter preserves the declared Swift field type until
/// the destination chooses its representation. Implementations may encode
/// directly into a frame or explicitly materialize owned fields.
public protocol PersistedFieldOutput {
    associatedtype Failure: Error & Sendable

    mutating func write<Value: FieldValueEncodable>(
        _ identity: FieldIdentity,
        value: borrowing Value,
        entity: String
    ) throws(PersistableEncodingFailure<Failure>)
}

public enum PersistableEncodingFailure<
    OutputFailure: Error & Sendable
>: Error, Sendable {
    case adaptation(PersistableEncodingError)
    case output(OutputFailure)
}

extension PersistableEncodingFailure where OutputFailure == Never {
    var adaptationError: PersistableEncodingError {
        switch self {
        case .adaptation(let error):
            return error
        case .output(let failure):
            switch failure {}
        }
    }
}
