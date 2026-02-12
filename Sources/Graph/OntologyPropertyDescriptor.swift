import Core

/// オントロジープロパティのメタデータ記述子。
///
/// `@Property` マクロにより `@Persistable` が自動生成する。
/// `RelationshipDescriptor` と同じ `Descriptor` パターンに準拠。
public struct OntologyPropertyDescriptor: Descriptor, Sendable, Codable, Hashable {

    /// 記述子名（`{TypeName}_{fieldName}` 形式）
    public let name: String

    /// フィールド名（Swift プロパティ名）
    public let fieldName: String

    /// OWL プロパティの IRI
    public let iri: String

    /// 表示ラベル（nil の場合は IRI のローカル名を使用）
    public let label: String?

    /// 対象型名（ObjectProperty の場合。nil なら DataProperty）
    public let targetTypeName: String?

    /// 対象型の逆引きフィールド名（ObjectProperty `to:` パラメータで指定）
    public let targetFieldName: String?

    /// ObjectProperty かどうか（`targetTypeName != nil`）
    public var isObjectProperty: Bool { targetTypeName != nil }

    public init(
        name: String,
        fieldName: String,
        iri: String,
        label: String? = nil,
        targetTypeName: String? = nil,
        targetFieldName: String? = nil
    ) {
        self.name = name
        self.fieldName = fieldName
        self.iri = iri
        self.label = label
        self.targetTypeName = targetTypeName
        self.targetFieldName = targetFieldName
    }
}
