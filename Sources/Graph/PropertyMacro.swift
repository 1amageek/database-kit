/// OWL プロパティとフィールドを紐付けるマーカーマクロ。
///
/// DataProperty（値プロパティ）の場合:
/// ```swift
/// @Property("http://example.org/onto#age")
/// var age: Int
/// ```
///
/// ObjectProperty（関係プロパティ）の場合:
/// ```swift
/// @Property("http://example.org/onto#worksFor",
///           to: \Department.id)
/// var departmentID: String?
/// ```
///
/// `to:` パラメータが指定されると ObjectProperty として扱われ、
/// `@Persistable` マクロが自動的に逆引きインデックスを生成する。
@attached(peer)
public macro Property(
    _ iri: String,
    label: String? = nil
) = #externalMacro(module: "GraphMacros", type: "PropertyMacro")

/// ObjectProperty 用: `to:` パラメータで対象フィールドを指定
@attached(peer)
public macro Property(
    _ iri: String,
    label: String? = nil,
    to keyPath: AnyKeyPath
) = #externalMacro(module: "GraphMacros", type: "PropertyMacro")
