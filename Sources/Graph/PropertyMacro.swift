/// OWL プロパティとフィールドを紐付けるマーカーマクロ。
///
/// `@Ontology` の IRI から名前空間を自動解決する。
/// ローカル名、CURIE、フル IRI のいずれも指定可能。
///
/// DataProperty（値プロパティ）の場合:
/// ```swift
/// @Ontology("ex:Employee")
/// struct Employee {
///     @OWLProperty("name")       // → "ex:name"
///     var name: String
///
///     @OWLProperty("foaf:mbox")  // → "foaf:mbox" (CURIE はそのまま)
///     var email: String
/// }
/// ```
///
/// ObjectProperty（関係プロパティ）の場合:
/// ```swift
/// @OWLProperty("worksFor", to: \Department.id)  // → "ex:worksFor"
/// var departmentID: String?
/// ```
///
/// `to:` パラメータが指定されると ObjectProperty として扱われ、
/// `@Persistable` マクロが自動的に逆引きインデックスを生成する。
@attached(peer)
public macro OWLProperty(
    _ iri: String,
    label: String? = nil
) = #externalMacro(module: "GraphMacros", type: "OWLPropertyMacro")

/// ObjectProperty 用: `to:` パラメータで対象フィールドを指定
@attached(peer)
public macro OWLProperty(
    _ iri: String,
    label: String? = nil,
    to keyPath: AnyKeyPath
) = #externalMacro(module: "GraphMacros", type: "OWLPropertyMacro")
