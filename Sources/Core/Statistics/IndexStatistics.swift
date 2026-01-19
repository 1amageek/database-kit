import Foundation

/// インデックスのビルド状態
public enum IndexBuildState: String, Sendable, Codable, Hashable {
    /// 利用可能（読み書き可能）
    case ready

    /// ビルド中（書き込みのみ）
    case building

    /// 無効化
    case disabled
}

/// インデックスの統計情報
public struct IndexStatistics: Sendable, Codable, Hashable {
    /// インデックス名
    public let indexName: String

    /// インデックスの種類（scalar, vector, fullText, etc.）
    public let kind: String

    /// エントリ数
    public let entryCount: Int64

    /// ストレージサイズ（バイト）
    public let storageSize: Int64

    /// ユニークキー数（該当する場合）
    public let uniqueKeyCount: Int64?

    /// ビルド状態
    public let state: IndexBuildState

    /// 最終使用日時
    public let lastUsed: Date?

    /// 使用回数
    public let usageCount: Int64?

    public init(
        indexName: String,
        kind: String,
        entryCount: Int64,
        storageSize: Int64,
        uniqueKeyCount: Int64? = nil,
        state: IndexBuildState,
        lastUsed: Date? = nil,
        usageCount: Int64? = nil
    ) {
        self.indexName = indexName
        self.kind = kind
        self.entryCount = entryCount
        self.storageSize = storageSize
        self.uniqueKeyCount = uniqueKeyCount
        self.state = state
        self.lastUsed = lastUsed
        self.usageCount = usageCount
    }
}
