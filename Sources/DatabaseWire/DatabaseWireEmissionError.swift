/// A failure that occurs before or during borrowed database-wire emission.
public enum DatabaseWireEmissionError<DestinationFailure: Error>: Error {
    /// Canonical measurement or encoding failed.
    case encoding(DatabaseWireError)

    /// The destination could not prepare for the exact encoded byte count.
    case destination(DestinationFailure)
}

extension DatabaseWireEmissionError: Sendable where DestinationFailure: Sendable {}

extension DatabaseWireEmissionError: Equatable where DestinationFailure: Equatable {}
