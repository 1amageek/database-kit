import Foundation

/// クエリ実行計画のタイプ
public enum PlanType: String, Sendable, Codable, Hashable {
    /// テーブルスキャン（全件走査）
    case tableScan = "table_scan"

    /// インデックススキャン（インデックス範囲走査）
    case indexScan = "index_scan"

    /// インデックスシーク（インデックス直接参照）
    case indexSeek = "index_seek"

    /// インデックスオンリー（インデックスのみで完結）
    case indexOnly = "index_only"

    /// 複数インデックスマージ
    case multiIndexMerge = "multi_index_merge"
}
