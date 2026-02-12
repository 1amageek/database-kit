import Core

/// オントロジークラスに紐付く Persistable 型を示すプロトコル。
///
/// `@Ontology` マクロにより自動準拠が生成される。
/// `ontologyClassIRI` は OWLOntology のクラス IRI に対応する。
public protocol OntologyEntity: Persistable {
    static var ontologyClassIRI: String { get }
    static var ontologyPropertyDescriptors: [OntologyPropertyDescriptor] { get }
}
