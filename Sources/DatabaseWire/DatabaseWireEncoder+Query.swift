import DatabaseTypes

@_spi(DatabaseExecution)
public extension DatabaseWireEncoder {
    /// Measures the canonical query success frame, preserving native projection failures.
    func measureQueryResponse(
        requestID: UInt64, resultCount: Int,
        body: (inout QueryResponseWriter) throws -> Void
    ) throws -> Int {
        try DatabaseWireWriter.measureProjection(limits: limits) { writer in
            try projectQueryResponse(requestID: requestID, resultCount: resultCount,
                into: &writer, body: body)
        }
    }

    /// Initializes a caller-owned destination during its synchronous byte borrow.
    func encodeQueryResponse(
        requestID: UInt64, resultCount: Int, into output: UnsafeMutableRawBufferPointer,
        body: (inout QueryResponseWriter) throws -> Void
    ) throws {
        // The caller owns and releases the final allocation. Byte alignment is
        // sufficient; exactly output.count bytes are initialized, never retained.
        // Bounds/deferred-error checks reject short, long or overflowing writes.
        guard output.count <= limits.maximumFrameBytes else {
            throw DatabaseWireError.frameTooLarge(actual: output.count, maximum: limits.maximumFrameBytes)
        }
        try DatabaseWireWriter.initializeProjection(into: output, limits: limits) { writer in
            try projectQueryResponse(requestID: requestID, resultCount: resultCount,
                into: &writer, body: body)
        }
    }

    private func projectQueryResponse(
        requestID: UInt64, resultCount: Int, into writer: inout DatabaseWireWriter,
        body: (inout QueryResponseWriter) throws -> Void
    ) throws {
        EnvelopeWireFormat.writeSuccessResponsePrefix(requestID: requestID,
            operation: .queryExecute, into: &writer)
        try writer.writeProjectedLengthPrefixed { payload in
            var response = try QueryResponseWriter(writer: payload, resultCount: resultCount)
            try body(&response)
            payload = try response.finish()
        }
    }
}
