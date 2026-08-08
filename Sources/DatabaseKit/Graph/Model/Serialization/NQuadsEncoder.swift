import DatabaseTypes

public struct NQuadsEncoder: Sendable {
    public init() {}

    public func encode(
        _ dataset: RDFDataset
    ) throws(RDFTermValidationError) -> String {
        try dataset.validate()
        let lines = dataset.quads.map(formatValidatedQuad(_:)).sorted()
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    /// Formats one validated RDF quad as a canonical N-Quads statement.
    ///
    /// The returned statement does not include a trailing newline so callers
    /// can write each result element directly to their output stream.
    public func format(
        _ quad: RDFQuad
    ) throws(RDFTermValidationError) -> String {
        try quad.validate()
        return formatValidatedQuad(quad)
    }

    private func formatValidatedQuad(_ quad: RDFQuad) -> String {
        var parts = [
            RDFSyntaxFormatter.formatNQuadsTerm(quad.subject.term),
            RDFSyntaxFormatter.formatNQuadsTerm(quad.predicate.term),
            RDFSyntaxFormatter.formatNQuadsTerm(quad.object)
        ]
        if let graph = quad.graph {
            parts.append(RDFSyntaxFormatter.formatNQuadsTerm(graph.term))
        }
        return parts.joined(separator: " ") + " ."
    }
}
