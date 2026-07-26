import DatabaseTypes

public struct NQuadsEncoder: Sendable {
    public init() {}

    public func encode(
        _ dataset: RDFDataset
    ) throws(RDFTermValidationError) -> String {
        try dataset.validate()
        let lines = dataset.quads
            .map(formatQuad(_:))
            .sorted()
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    private func formatQuad(_ quad: RDFQuad) -> String {
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
