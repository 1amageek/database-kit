import Foundation

/// クエリ実行計画
public struct QueryPlan: Sendable, Codable, Hashable {
    /// 計画タイプ
    public let planType: PlanType

    /// 選択されたインデックス（使用する場合）
    public let selectedIndex: String?

    /// 推定コスト
    public let estimatedCost: Double

    /// 推定行数
    public let estimatedRows: Int64

    /// インデックスで処理される条件
    public let indexConditions: [String]

    /// フィルタで処理される条件（インデックス後の絞り込み）
    public let filterConditions: [String]

    /// ソートが必要かどうか
    public let sortRequired: Bool

    /// 検討された代替プラン
    public let alternatives: [AlternativePlan]?

    public init(
        planType: PlanType,
        selectedIndex: String? = nil,
        estimatedCost: Double,
        estimatedRows: Int64,
        indexConditions: [String] = [],
        filterConditions: [String] = [],
        sortRequired: Bool = false,
        alternatives: [AlternativePlan]? = nil
    ) {
        self.planType = planType
        self.selectedIndex = selectedIndex
        self.estimatedCost = estimatedCost
        self.estimatedRows = estimatedRows
        self.indexConditions = indexConditions
        self.filterConditions = filterConditions
        self.sortRequired = sortRequired
        self.alternatives = alternatives
    }
}

/// 代替クエリプラン（選択されなかったプラン）
public struct AlternativePlan: Sendable, Codable, Hashable {
    /// 計画タイプ
    public let planType: PlanType

    /// 選択されたインデックス
    public let selectedIndex: String?

    /// 推定コスト
    public let estimatedCost: Double

    /// 選択されなかった理由
    public let reason: String

    public init(
        planType: PlanType,
        selectedIndex: String? = nil,
        estimatedCost: Double,
        reason: String
    ) {
        self.planType = planType
        self.selectedIndex = selectedIndex
        self.estimatedCost = estimatedCost
        self.reason = reason
    }
}

/// クエリ実行統計（EXPLAIN ANALYZE の結果）
public struct QueryExecutionStats: Sendable, Codable, Hashable {
    /// 実行計画
    public let plan: QueryPlan

    /// 実際の行数
    public let actualRows: Int64

    /// 実行時間（秒）
    public let executionTime: TimeInterval

    /// 読み取りバイト数
    public let bytesRead: Int64

    /// トランザクションリトライ回数
    public let transactionRetries: Int

    // MARK: - FDB固有

    /// 読み取りバージョン（FDB固有）
    public let readVersion: UInt64?

    /// コンフリクト範囲数（FDB固有）
    public let conflictRanges: Int?

    public init(
        plan: QueryPlan,
        actualRows: Int64,
        executionTime: TimeInterval,
        bytesRead: Int64,
        transactionRetries: Int = 0,
        readVersion: UInt64? = nil,
        conflictRanges: Int? = nil
    ) {
        self.plan = plan
        self.actualRows = actualRows
        self.executionTime = executionTime
        self.bytesRead = bytesRead
        self.transactionRetries = transactionRetries
        self.readVersion = readVersion
        self.conflictRanges = conflictRanges
    }
}
