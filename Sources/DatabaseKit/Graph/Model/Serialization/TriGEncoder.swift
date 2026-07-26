import DatabaseTypes

public struct TriGEncoder: Sendable {
    public init() {}

    public func encode(
        _ dataset: RDFDataset
    ) throws(RDFTermValidationError) -> String {
        try dataset.validate()

        var lines: [String] = []
        for (prefix, namespace) in dataset.prefixes.sorted(
            by: { $0.key < $1.key }
        ) {
            lines.append("@prefix \(prefix): <\(namespace)> .")
        }
        if let baseIRI = dataset.baseIRI {
            lines.append("@base <\(baseIRI)> .")
        }
        if !lines.isEmpty {
            lines.append("")
        }

        let grouped = Dictionary(grouping: dataset.quads, by: { $0.graph })
        let defaultQuads = grouped[nil, default: []]
        for line in defaultQuads.map({
            formatTriple($0, prefixes: dataset.prefixes)
        }).sorted() {
            lines.append(line)
        }

        let namedGraphs = grouped.keys.compactMap { $0 }.sorted {
            compareTerms($0.term, $1.term)
        }
        for graph in namedGraphs {
            if !lines.isEmpty, lines.last != "" {
                lines.append("")
            }
            let graphName = RDFSyntaxFormatter.formatTriGTerm(
                graph.term,
                prefixes: dataset.prefixes
            )
            lines.append("\(graphName) {")
            let graphQuads = grouped[graph, default: []]
                .map {
                    formatTriple(
                        $0,
                        prefixes: dataset.prefixes,
                        indent: "    "
                    )
                }
                .sorted()
            lines.append(contentsOf: graphQuads)
            lines.append("}")
        }

        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    private func formatTriple(
        _ quad: RDFQuad,
        prefixes: [String: String],
        indent: String = ""
    ) -> String {
        [
            indent + RDFSyntaxFormatter.formatTriGTerm(
                quad.subject.term,
                prefixes: prefixes
            ),
            RDFSyntaxFormatter.formatTriGTerm(
                quad.predicate.term,
                prefixes: prefixes
            ),
            RDFSyntaxFormatter.formatTriGTerm(
                quad.object,
                prefixes: prefixes
            )
        ].joined(separator: " ") + " ."
    }

    private func compareTerms(_ lhs: RDFTerm, _ rhs: RDFTerm) -> Bool {
        RDFSyntaxFormatter.formatNQuadsTerm(lhs)
            < RDFSyntaxFormatter.formatNQuadsTerm(rhs)
    }
}
