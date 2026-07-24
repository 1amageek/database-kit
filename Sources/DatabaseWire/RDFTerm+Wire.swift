import DatabaseKit
import DatabaseTypes

extension RDFTerm {
    public func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        try writer.writeCanonicalRDFTerm(self)
    }

    public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        self = try reader.readCanonicalRDFTerm(role: .term)
    }
}

extension DatabaseWireReader {
    mutating func readCanonicalRDFTerm(
        role: RDFTermRole
    ) throws(DatabaseWireError) -> RDFTerm {
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
        let codecLimits = RDFTermCodecLimits(
            validatedMaximumBytes: self.limits.maximumByteStringBytes,
            maximumDepth: remainingDepth,
            maximumObjectCount: remainingObjectCount
        )
        let result: RDFTermDecodingResult
        do {
            result = try RDFTermCodec.decodeWithMetrics(
                bytes,
                role: role,
                limits: codecLimits
            )
        } catch let error {
            throw mapCanonicalRDFTermError(error)
        }
        try registerObjects(result.objectCount)
        return result.term
    }

    private func mapCanonicalRDFTermError(
        _ error: RDFTermCodecError
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
