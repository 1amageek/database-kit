import DatabaseKit
import DatabaseTypes

/// Bounded encoding for opaque state owned by the database server runtime.
///
/// This SPI does not create operation identifiers or envelopes. It allows
/// server-owned continuations and persistent job state to share the canonical
/// scalar representation and limits used by DatabaseWire.
@_spi(DatabaseServer)
public enum ServerPayloadEncoder {
    public static func encode<Value: ServerPayloadValue>(
        _ value: Value,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) {
            (writer: inout DatabaseWireWriter)
                throws(DatabaseWireError) in
            try value.encode(into: &writer)
        }
    }

    public static func encode(
        _ value: RDFQuad,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try encodeCanonical(value, limits: limits)
    }

    public static func encode(
        _ value: ValidationReport.Issue,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try encodeCanonical(value, limits: limits)
    }

    public static func encode(
        _ value: GraphAlgorithmOperation.Term,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try encodeCanonical(value, limits: limits)
    }

    public static func emit<DestinationFailure: Error>(
        _ value: RDFQuad,
        limits: DatabaseWireLimits = .default,
        prepare: (Int) throws(DestinationFailure) -> Void,
        consume: (UnsafeRawBufferPointer) -> Void
    ) throws(DatabaseWireEmissionError<DestinationFailure>) {
        try emitCanonical(
            value,
            limits: limits,
            prepare: prepare,
            consume: consume
        )
    }

    public static func emit<DestinationFailure: Error>(
        _ value: GraphAlgorithmOperation.Term,
        limits: DatabaseWireLimits = .default,
        prepare: (Int) throws(DestinationFailure) -> Void,
        consume: (UnsafeRawBufferPointer) -> Void
    ) throws(DatabaseWireEmissionError<DestinationFailure>) {
        try emitCanonical(
            value,
            limits: limits,
            prepare: prepare,
            consume: consume
        )
    }

    private static func emitCanonical<
        Value: WireValue,
        DestinationFailure: Error
    >(
        _ value: Value,
        limits: DatabaseWireLimits,
        prepare: (Int) throws(DestinationFailure) -> Void,
        consume: (UnsafeRawBufferPointer) -> Void
    ) throws(DatabaseWireEmissionError<DestinationFailure>) {
        try DatabaseWireWriter.emit(
            limits: limits,
            prepare: prepare,
            consume: consume
        ) {
            (writer: inout DatabaseWireWriter)
                throws(DatabaseWireError) in
            try value.encode(into: &writer)
        }
    }

    private static func encodeCanonical<Value: WireValue>(
        _ value: Value,
        limits: DatabaseWireLimits
    ) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) {
            (writer: inout DatabaseWireWriter)
                throws(DatabaseWireError) in
            try value.encode(into: &writer)
        }
    }
}
