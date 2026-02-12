// OWLOntologyBuilder.swift
// Graph - Result builder DSL for OWLOntology construction

// MARK: - OWLOntologyComponent

/// OWLOntology に追加可能な要素のプロトコル
public protocol OWLOntologyComponent {
    func apply(to ontology: inout OWLOntology)
}

extension OWLClass: OWLOntologyComponent {
    public func apply(to ontology: inout OWLOntology) {
        ontology.classes.append(self)
    }
}

extension OWLObjectProperty: OWLOntologyComponent {
    public func apply(to ontology: inout OWLOntology) {
        ontology.objectProperties.append(self)
    }
}

extension OWLDataProperty: OWLOntologyComponent {
    public func apply(to ontology: inout OWLOntology) {
        ontology.dataProperties.append(self)
    }
}

extension OWLAnnotationProperty: OWLOntologyComponent {
    public func apply(to ontology: inout OWLOntology) {
        ontology.annotationProperties.append(self)
    }
}

extension OWLNamedIndividual: OWLOntologyComponent {
    public func apply(to ontology: inout OWLOntology) {
        ontology.individuals.append(self)
    }
}

extension OWLAxiom: OWLOntologyComponent {
    public func apply(to ontology: inout OWLOntology) {
        ontology.axioms.append(self)
    }
}

// MARK: - @resultBuilder

@resultBuilder
public struct OWLOntologyBuilder {

    public static func buildExpression(_ expression: OWLOntologyComponent) -> [OWLOntologyComponent] {
        [expression]
    }

    public static func buildExpression(_ expression: [OWLOntologyComponent]) -> [OWLOntologyComponent] {
        expression
    }

    public static func buildBlock(_ components: [OWLOntologyComponent]...) -> [OWLOntologyComponent] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [OWLOntologyComponent]?) -> [OWLOntologyComponent] {
        component ?? []
    }

    public static func buildEither(first component: [OWLOntologyComponent]) -> [OWLOntologyComponent] {
        component
    }

    public static func buildEither(second component: [OWLOntologyComponent]) -> [OWLOntologyComponent] {
        component
    }

    public static func buildArray(_ components: [[OWLOntologyComponent]]) -> [OWLOntologyComponent] {
        components.flatMap { $0 }
    }
}
