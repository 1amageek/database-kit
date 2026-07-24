import DatabaseTypes
/// クエリ実行計画
public struct QueryPlan: Sendable, Codable, Hashable {
    /// 計画タイプ
    public let planType: PlanType

    /// 選択されたインデックス（使用する場合）
    public let selectedIndex: String?

    /// Estimated cost, or `nil` when no statistics-backed cost model ran.
    public let estimatedCost: Double?

    /// Estimated row count, or `nil` when row-count statistics are unavailable.
    public let estimatedRows: Int64?

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
        estimatedCost: Double? = nil,
        estimatedRows: Int64? = nil,
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

    /// Estimated cost, or `nil` when no statistics-backed cost model ran.
    public let estimatedCost: Double?

    /// 選択されなかった理由
    public let reason: String

    public init(
        planType: PlanType,
        selectedIndex: String? = nil,
        estimatedCost: Double? = nil,
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
    public let executionTime: Double

    /// Bytes read, or `nil` when execution instrumentation did not measure it.
    public let bytesRead: Int64?

    /// Transaction retry count, or `nil` when it was not measured.
    public let transactionRetries: Int?

    // MARK: - FDB固有

    /// 読み取りバージョン（FDB固有）
    public let readVersion: UInt64?

    /// コンフリクト範囲数（FDB固有）
    public let conflictRanges: Int?

    public init(
        plan: QueryPlan,
        actualRows: Int64,
        executionTime: Double,
        bytesRead: Int64? = nil,
        transactionRetries: Int? = nil,
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
