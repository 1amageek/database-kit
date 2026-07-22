extension TimeWindowLeaderboardIndexKind {
    public init(
        canonical kind: IndexKindMetadata
    ) throws(IndexKindMetadataError) {
        try kind.validateIdentity(
            identifier: Self.identifier,
            subspaceStructure: Self.subspaceStructure
        )
        try kind.validateMetadataKeys(
            required: ["window", "windowCount"],
            optional: ["windowDurationSeconds"]
        )
        try kind.validateFieldCount(minimum: 1)

        let windowCount = try kind.requireInt("windowCount")
        guard windowCount > 0 else {
            throw .invalidMetadata(identifier: kind.identifier, key: "windowCount")
        }

        let window: LeaderboardWindowType
        switch try kind.requireString("window") {
        case "hourly":
            try Self.rejectCustomDuration(in: kind)
            window = .hourly
        case "daily":
            try Self.rejectCustomDuration(in: kind)
            window = .daily
        case "weekly":
            try Self.rejectCustomDuration(in: kind)
            window = .weekly
        case "monthly":
            try Self.rejectCustomDuration(in: kind)
            window = .monthly
        case "custom":
            let duration = try kind.requireDouble("windowDurationSeconds")
            guard duration > 0 else {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "windowDurationSeconds"
                )
            }
            window = .custom(duration: duration)
        default:
            throw .invalidMetadata(identifier: kind.identifier, key: "window")
        }

        self.init(
            scoreFieldName: kind.fieldNames[kind.fieldNames.count - 1],
            groupByFieldNames: Array(kind.fieldNames.dropLast()),
            window: window,
            windowCount: windowCount
        )
    }

    private static func rejectCustomDuration(
        in kind: IndexKindMetadata
    ) throws(IndexKindMetadataError) {
        guard kind.metadata["windowDurationSeconds"] == nil else {
            throw .unexpectedMetadata(
                identifier: kind.identifier,
                key: "windowDurationSeconds"
            )
        }
    }
}
