/// OWL オントロジークラスと Persistable 型を紐付けるマクロ。
///
/// `OntologyEntity` プロトコルへの自動準拠を生成し、
/// `ontologyClassIRI` と `ontologyPropertyDescriptors` を追加する。
///
/// **Usage**:
/// ```swift
/// @Persistable
/// @Ontology("http://example.org/onto#Employee")
/// struct Employee {
///     @Property("http://example.org/onto#name")
///     var name: String
///
///     @Property("http://example.org/onto#worksFor", to: \Department.id)
///     var departmentID: String?
/// }
/// ```
///
/// **Generated code**:
/// - `static var ontologyClassIRI: String` — OWL クラス IRI
/// - `static var ontologyPropertyDescriptors: [OntologyPropertyDescriptor]` — `@Property` フィールドのメタデータ
/// - `OntologyEntity` プロトコル準拠
@attached(member, names: named(ontologyClassIRI), named(ontologyPropertyDescriptors))
@attached(extension, conformances: OntologyEntity)
public macro Ontology(_ iri: String) = #externalMacro(module: "GraphMacros", type: "OntologyMacro")
