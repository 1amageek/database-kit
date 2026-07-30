import DatabaseTypes

/// A concrete source of canonical fields consumed by macro-generated model
/// reconstruction.
///
/// The source owns field ordering, framing, and boundary failures. Generated
/// model code asks for fields by stable identity and performs the statically
/// selected Swift value conversion.
public protocol PersistedFieldInput {
    associatedtype Failure: Error & Sendable

    mutating func readField(
        _ identity: FieldIdentity,
        entity: String
    ) throws(PersistableDecodingFailure<Failure>) -> FieldValue?

    mutating func finish(
        entity: String
    ) throws(PersistableDecodingFailure<Failure>)
}

public extension PersistedFieldInput where Failure == Never {
    /// Runs a compiled model decoder over an input whose transport boundary
    /// cannot fail, preserving only canonical model adaptation failures.
    mutating func decode<Model>(
        _ body: (inout Self) throws(PersistableDecodingFailure<Never>) -> Model
    ) throws(PersistableDecodingError) -> Model {
        do {
            return try body(&self)
        } catch {
            throw error.adaptationError
        }
    }
}

/// Preserves whether model reconstruction failed at the concrete input
/// boundary or while adapting a canonical field to the declared Swift type.
public enum PersistableDecodingFailure<
    InputFailure: Error & Sendable
>: Error, Sendable {
    case input(InputFailure)
    case adaptation(PersistableDecodingError)
}

public extension PersistableDecodingFailure where InputFailure == Never {
    var adaptationError: PersistableDecodingError {
        switch self {
        case .input(let failure):
            switch failure {}
        case .adaptation(let error):
            return error
        }
    }
}
