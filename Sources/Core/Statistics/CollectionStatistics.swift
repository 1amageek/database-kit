import Foundation

/// コレクション（Type）の統計情報
public struct CollectionStatistics: Sendable, Codable, Hashable {
    /// 型名
    public let typeName: String

    /// ドキュメント数
    public let documentCount: Int64

    /// ストレージサイズ（バイト）
    public let storageSize: Int64

    /// 平均ドキュメントサイズ（バイト）
    public let avgDocumentSize: Int

    /// 最終更新日時
    public let lastModified: Date?

    // MARK: - FDB固有

    /// キー範囲の開始（FDB固有）
    public let keyRangeStart: [UInt8]?

    /// キー範囲の終了（FDB固有）
    public let keyRangeEnd: [UInt8]?

    public init(
        typeName: String,
        documentCount: Int64,
        storageSize: Int64,
        avgDocumentSize: Int,
        lastModified: Date? = nil,
        keyRangeStart: [UInt8]? = nil,
        keyRangeEnd: [UInt8]? = nil
    ) {
        self.typeName = typeName
        self.documentCount = documentCount
        self.storageSize = storageSize
        self.avgDocumentSize = avgDocumentSize
        self.lastModified = lastModified
        self.keyRangeStart = keyRangeStart
        self.keyRangeEnd = keyRangeEnd
    }
}
