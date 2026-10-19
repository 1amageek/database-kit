import DatabaseTypes

@_spi(DatabaseExecution)
public extension DatabaseWireEncoder {
    /// Measures the full SQL success frame, preserving native projection failures.
    func measureSQLResponse(
        requestID: UInt64, resultCount: Int,
        body: (inout SQLResponseWriter) throws -> Void
    ) throws -> Int {
        try DatabaseWireWriter.measureProjection(limits: limits) { writer in
            try projectSQLResponse(requestID: requestID, resultCount: resultCount,
                into: &writer, body: body)
        }
    }

    /// Initializes a caller-owned destination during its synchronous byte borrow.
    func encodeSQLResponse(
        requestID: UInt64, resultCount: Int, into output: UnsafeMutableRawBufferPointer,
        body: (inout SQLResponseWriter) throws -> Void
    ) throws {
        // The caller owns and releases the final allocation. Byte alignment is
        // sufficient; exactly output.count bytes are initialized, never retained.
        // Bounds/deferred-error checks reject short, long or overflowing writes.
        guard output.count <= limits.maximumFrameBytes else {
            throw DatabaseWireError.frameTooLarge(actual: output.count, maximum: limits.maximumFrameBytes)
        }
        try DatabaseWireWriter.initializeProjection(into: output, limits: limits) { writer in
            try projectSQLResponse(requestID: requestID, resultCount: resultCount,
                into: &writer, body: body)
        }
    }

    private func projectSQLResponse(
        requestID: UInt64, resultCount: Int, into writer: inout DatabaseWireWriter,
        body: (inout SQLResponseWriter) throws -> Void
    ) throws {
        EnvelopeWireFormat.writeSuccessResponsePrefix(requestID: requestID,
            operation: .sqlExecute, into: &writer)
        try writer.writeProjectedLengthPrefixed { payload in
            var response = try SQLResponseWriter(writer: payload, resultCount: resultCount)
            try body(&response)
            payload = try response.finish()
        }
    }
}
