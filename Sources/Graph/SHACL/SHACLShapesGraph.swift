// SHACLShapesGraph.swift
// Graph - SHACL shapes graph container
//
// Reference: W3C SHACL §2.1 (Shapes Graph)
// https://www.w3.org/TR/shacl/#shapes-graph

import Foundation

/// SHACL Shapes Graph — a collection of shapes
///
/// A shapes graph defines the constraints that a data graph must satisfy.
/// It contains shape definitions, prefix mappings, and configuration.
///
/// **Example**:
/// ```swift
/// let shapesGraph = SHACLShapesGraph(
///     iri: "http://example.org/shapes/person",
///     shapes: [
///         .node(NodeShape(
///             iri: "ex:PersonShape",
///             targets: [.class_("ex:Person")],
///             propertyShapes: [
///                 PropertyShape(
///                     path: .predicate("ex:name"),
///                     constraints: [.minCount(1), .datatype("xsd:string")]
///                 )
///             ]
///         ))
///     ],
///     prefixes: .standard
/// )
/// ```
///
/// Reference: W3C SHACL §2.1
public struct SHACLShapesGraph: Sendable, Codable, Hashable {

    /// IRI identifying this shapes graph
    public let iri: String

    /// All shapes in this graph
    public var shapes: [SHACLShape]

    /// Prefix mappings for IRI expansion/compaction
    public var prefixes: PrefixMap

    /// Entailment regime for validation
    public var entailment: SHACLEntailment

    public init(
        iri: String,
        shapes: [SHACLShape] = [],
        prefixes: PrefixMap = .standard,
        entailment: SHACLEntailment = .none
    ) {
        self.iri = iri
        self.shapes = shapes
        self.prefixes = prefixes
        self.entailment = entailment
    }
}

// MARK: - SHACLEntailment

/// SHACL Entailment Regime
///
/// Determines whether inference is applied to the data graph before validation.
///
/// Reference: W3C SHACL §3.2
public enum SHACLEntailment: String, Sendable, Codable, Hashable {
    /// No entailment — validate raw data graph (SHACL Core default)
    case none

    /// RDFS entailment — apply RDFS inference rules
    case rdfs

    /// OWL entailment — apply OWL reasoning (requires loaded ontology)
    case owl
}

// MARK: - Convenience

extension SHACLShapesGraph {
    /// Add a shape to this graph
    @discardableResult
    public mutating func addShape(_ shape: SHACLShape) -> Self {
        shapes.append(shape)
        return self
    }

    /// All node shapes in this graph
    public var nodeShapes: [NodeShape] {
        shapes.compactMap { shape in
            if case .node(let ns) = shape { return ns }
            return nil
        }
    }

    /// All property shapes in this graph
    public var propertyShapes: [PropertyShape] {
        shapes.compactMap { shape in
            if case .property(let ps) = shape { return ps }
            return nil
        }
    }

    /// Active (non-deactivated) shapes
    public var activeShapes: [SHACLShape] {
        shapes.filter { !$0.isDeactivated }
    }

    /// Find a shape by IRI
    public func findShape(iri: String) -> SHACLShape? {
        shapes.first { $0.iri == iri }
    }

    /// All target class IRIs referenced in this graph
    public var targetClassIRIs: Set<String> {
        var result = Set<String>()
        for shape in shapes {
            for target in shape.targets {
                if case .class_(let iri) = target {
                    result.insert(iri)
                }
            }
        }
        return result
    }

    /// Statistics about this shapes graph
    public var statistics: Statistics {
        Statistics(
            shapeCount: shapes.count,
            nodeShapeCount: nodeShapes.count,
            propertyShapeCount: propertyShapes.count,
            activeShapeCount: activeShapes.count,
            prefixCount: prefixes.count
        )
    }

    public struct Statistics: Sendable {
        public let shapeCount: Int
        public let nodeShapeCount: Int
        public let propertyShapeCount: Int
        public let activeShapeCount: Int
        public let prefixCount: Int
    }
}

// MARK: - CustomStringConvertible

extension SHACLShapesGraph: CustomStringConvertible {
    public var description: String {
        let stats = statistics
        return "SHACLShapesGraph(\(iri), shapes: \(stats.shapeCount), entailment: \(entailment))"
    }
}
