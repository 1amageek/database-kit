public import DatabaseValue

extension DatabaseRDFTerm {
    public func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try writer.writeCanonicalRDFTerm(self)
    }

    public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        self = try reader.readCanonicalRDFTerm(role: .term)
    }
}

extension DatabaseWireReader {
    mutating func readCanonicalRDFTerm(
        role: DatabaseRDFTermRole
    ) throws(DatabaseWireError) -> DatabaseRDFTerm {
        let bytes = try readBytes()
        guard limits.maximumObjectCount > registeredObjectCount else {
            let (actual, overflow) = registeredObjectCount
                .addingReportingOverflow(1)
            throw .objectBudgetExceeded(
                actual: overflow ? Int.max : actual,
                maximum: limits.maximumObjectCount
            )
        }
        let remainingObjectCount = limits.maximumObjectCount
            - registeredObjectCount
        guard limits.maximumNestingDepth >= currentNestingDepth else {
            throw .nestingTooDeep(
                actual: currentNestingDepth,
                maximum: limits.maximumNestingDepth
            )
        }
        let remainingDepth = limits.maximumNestingDepth - currentNestingDepth
        let codecLimits = DatabaseRDFTermCodecLimits(
            maximumBytes: self.limits.maximumByteStringBytes,
            maximumDepth: remainingDepth,
            maximumObjectCount: remainingObjectCount
        )
        do {
            let result = try DatabaseRDFTermCodec.decodeWithMetrics(
                bytes,
                role: role,
                limits: codecLimits
            )
            try registerObjects(result.objectCount)
            return result.term
        } catch let error as DatabaseRDFTermCodecError {
            throw mapCanonicalRDFTermError(error)
        } catch let error as DatabaseWireError {
            throw error
        } catch {
            preconditionFailure("Unexpected RDF term wire decoding error")
        }
    }

    private func mapCanonicalRDFTermError(
        _ error: DatabaseRDFTermCodecError
    ) -> DatabaseWireError {
        switch error {
        case .maximumBytesExceeded(let actual, _):
            return .byteStringTooLarge(
                actual: actual,
                maximum: limits.maximumByteStringBytes
            )
        case .maximumDepthExceeded(let actual, _):
            let (combined, overflow) = currentNestingDepth
                .addingReportingOverflow(actual)
            guard !overflow else { return .byteCountOverflow }
            return .nestingTooDeep(
                actual: combined,
                maximum: limits.maximumNestingDepth
            )
        case .maximumObjectCountExceeded(let actual, _):
            let (combined, overflow) = registeredObjectCount
                .addingReportingOverflow(actual)
            guard !overflow else { return .byteCountOverflow }
            return .objectBudgetExceeded(
                actual: combined,
                maximum: limits.maximumObjectCount
            )
        default:
            return .invalidCanonicalRDFTerm(error)
        }
    }
}
