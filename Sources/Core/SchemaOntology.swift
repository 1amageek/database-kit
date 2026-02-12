/// Schema にオントロジーを紐付けるためのプロトコル。
///
/// Core モジュールは Graph に依存できないため、
/// この抽象プロトコルを Core 側に定義し、
/// Graph モジュールで `OWLOntology` が準拠する。
public protocol SchemaOntology: Sendable {
    var iri: String { get }
}
