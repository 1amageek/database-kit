import DatabaseKit

extension SchemaJSONCodec {
    func encodeIndexDefinition(_ value: IndexDefinition) throws -> JSONValue {
        switch value {
        case .scalar: return kindNode("scalar")
        case .count: return kindNode("count")
        case .sum: return kindNode("sum")
        case .minimum: return kindNode("minimum")
        case .maximum: return kindNode("maximum")
        case .average: return kindNode("average")
        case .version(let strategy):
            return .object([
                ("kind", .string("version")),
                ("strategy", encodeVersionStrategy(strategy)),
            ])
        case .countUpdates: return kindNode("countUpdates")
        case .countNotNull: return kindNode("countNotNull")
        case .bitmap: return kindNode("bitmap")
        case .timeWindowLeaderboard(let window, let windowCount):
            return .object([
                ("kind", .string("timeWindowLeaderboard")),
                ("window", encodeLeaderboardWindow(window)),
                ("windowCount", .number(String(windowCount))),
            ])
        case .distinct(let precision):
            return .object([
                ("kind", .string("distinct")),
                ("precision", .number(String(precision))),
            ])
        case .percentile(let compression):
            return .object([
                ("kind", .string("percentile")),
                ("compressionBits", .string(hex(compression.bitPattern, digits: 16))),
            ])
        case .vector(let dimensions, let metric):
            return .object([
                ("kind", .string("vector")),
                ("dimensions", .number(String(dimensions))),
                ("metric", .string(metric.rawValue)),
            ])
        case .fullText(let tokenizer, let storePositions, let ngramSize, let minTermLength):
            return .object([
                ("kind", .string("fullText")),
                ("tokenizer", .string(tokenizer.rawValue)),
                ("storePositions", .bool(storePositions)),
                ("ngramSize", .number(String(ngramSize))),
                ("minTermLength", .number(String(minTermLength))),
            ])
        case .autocomplete(let minPrefixLength, let maxPrefixLength):
            return .object([
                ("kind", .string("autocomplete")),
                ("minPrefixLength", .number(String(minPrefixLength))),
                ("maxPrefixLength", .number(String(maxPrefixLength))),
            ])
        case .spatial(let encoding, let level):
            return .object([
                ("kind", .string("spatial")),
                ("encoding", .string(encoding.rawValue)),
                ("level", .number(String(level))),
            ])
        case .rank: return kindNode("rank")
        case .permuted(let pattern):
            return .object([
                ("kind", .string("permuted")),
                ("pattern", encodePermutation(pattern)),
            ])
        case .propertyGraph(let strategy, let label):
            return .object([
                ("kind", .string("propertyGraph")),
                ("strategy", .string(strategy.rawValue)),
                ("label", .string(label == .field ? "field" : "implicit")),
            ])
        case .rdfDataset: return kindNode("rdfDataset")
        }
    }

    func decodeIndexDefinition(
        _ node: JSONValue,
        path: String
    ) throws -> IndexDefinition {
        let object = try JSONObject(node, path: path)
        let kind = try object.required("kind").string(path: object.child("kind"))
        switch kind {
        case "scalar": try object.validateKeys(["kind"]); return .scalar
        case "count": try object.validateKeys(["kind"]); return .count
        case "sum": try object.validateKeys(["kind"]); return .sum
        case "minimum": try object.validateKeys(["kind"]); return .minimum
        case "maximum": try object.validateKeys(["kind"]); return .maximum
        case "average": try object.validateKeys(["kind"]); return .average
        case "version":
            try object.validateKeys(["kind", "strategy"])
            return .version(
                strategy: try decodeVersionStrategy(
                    object.required("strategy"),
                    path: object.child("strategy")
                )
            )
        case "countUpdates": try object.validateKeys(["kind"]); return .countUpdates
        case "countNotNull": try object.validateKeys(["kind"]); return .countNotNull
        case "bitmap": try object.validateKeys(["kind"]); return .bitmap
        case "timeWindowLeaderboard":
            try object.validateKeys(["kind", "window", "windowCount"])
            return .timeWindowLeaderboard(
                window: try decodeLeaderboardWindow(
                    object.required("window"),
                    path: object.child("window")
                ),
                windowCount: try integer(object, "windowCount")
            )
        case "distinct":
            try object.validateKeys(["kind", "precision"])
            return .distinct(precision: try integer(object, "precision"))
        case "percentile":
            try object.validateKeys(["kind", "compressionBits"])
            let bits: UInt64 = try decodeHex(
                object.required("compressionBits").string(
                    path: object.child("compressionBits")
                ),
                digits: 16,
                path: object.child("compressionBits")
            )
            let value = Double(bitPattern: bits)
            guard value.isFinite else {
                throw SchemaJSONError.invalidValue(
                    path: object.child("compressionBits"),
                    reason: "non-finite percentile compression"
                )
            }
            return .percentile(compression: value)
        case "vector":
            try object.validateKeys(["kind", "dimensions", "metric"])
            let rawMetric = try object.required("metric").string(path: object.child("metric"))
            guard let metric = VectorMetric(rawValue: rawMetric) else {
                throw invalidEnum(object.child("metric"), rawMetric)
            }
            return .vector(dimensions: try integer(object, "dimensions"), metric: metric)
        case "fullText":
            try object.validateKeys([
                "kind", "tokenizer", "storePositions", "ngramSize", "minTermLength",
            ])
            let rawTokenizer = try object.required("tokenizer").string(
                path: object.child("tokenizer")
            )
            guard let tokenizer = TokenizationStrategy(rawValue: rawTokenizer) else {
                throw invalidEnum(object.child("tokenizer"), rawTokenizer)
            }
            return .fullText(
                tokenizer: tokenizer,
                storePositions: try object.required("storePositions").bool(
                    path: object.child("storePositions")
                ),
                ngramSize: try integer(object, "ngramSize"),
                minTermLength: try integer(object, "minTermLength")
            )
        case "autocomplete":
            try object.validateKeys(["kind", "minPrefixLength", "maxPrefixLength"])
            return .autocomplete(
                minPrefixLength: try integer(object, "minPrefixLength"),
                maxPrefixLength: try integer(object, "maxPrefixLength")
            )
        case "spatial":
            try object.validateKeys(["kind", "encoding", "level"])
            let rawEncoding = try object.required("encoding").string(
                path: object.child("encoding")
            )
            guard let encoding = SpatialEncoding(rawValue: rawEncoding) else {
                throw invalidEnum(object.child("encoding"), rawEncoding)
            }
            return .spatial(encoding: encoding, level: try integer(object, "level"))
        case "rank": try object.validateKeys(["kind"]); return .rank
        case "permuted":
            try object.validateKeys(["kind", "pattern"])
            return .permuted(
                try decodePermutation(
                    object.required("pattern"),
                    path: object.child("pattern")
                )
            )
        case "propertyGraph":
            try object.validateKeys(["kind", "strategy", "label"])
            let rawStrategy = try object.required("strategy").string(
                path: object.child("strategy")
            )
            guard let strategy = PropertyGraphIndexStrategy(rawValue: rawStrategy) else {
                throw invalidEnum(object.child("strategy"), rawStrategy)
            }
            let rawLabel = try object.required("label").string(path: object.child("label"))
            let label: PropertyGraphLabelSource
            switch rawLabel {
            case "field": label = .field
            case "implicit": label = .implicit
            default: throw invalidEnum(object.child("label"), rawLabel)
            }
            return .propertyGraph(strategy: strategy, label: label)
        case "rdfDataset": try object.validateKeys(["kind"]); return .rdfDataset
        default:
            throw SchemaJSONError.invalidValue(
                path: object.child("kind"),
                reason: "unknown index definition '\(kind)'"
            )
        }
    }
}

extension SchemaJSONCodec {
    func encodeVersionStrategy(_ value: VersionHistoryStrategy) -> JSONValue {
        switch value {
        case .keepAll: return kindNode("keepAll")
        case .keepLast(let count):
            return .object([
                ("kind", .string("keepLast")),
                ("count", .number(String(count))),
            ])
        case .keepForDuration(let duration):
            return .object([
                ("kind", .string("keepForDuration")),
                ("seconds", .number(String(duration.seconds))),
                ("nanoseconds", .number(String(duration.nanoseconds))),
            ])
        }
    }

    func decodeVersionStrategy(
        _ node: JSONValue,
        path: String
    ) throws -> VersionHistoryStrategy {
        let object = try JSONObject(node, path: path)
        let kind = try object.required("kind").string(path: object.child("kind"))
        switch kind {
        case "keepAll":
            try object.validateKeys(["kind"])
            return .keepAll
        case "keepLast":
            try object.validateKeys(["kind", "count"])
            return .keepLast(try integer(object, "count"))
        case "keepForDuration":
            try object.validateKeys(["kind", "seconds", "nanoseconds"])
            return .keepForDuration(
                try TimeSpan(
                    seconds: integer(object, "seconds"),
                    nanoseconds: integer(object, "nanoseconds")
                )
            )
        default: throw invalidEnum(object.child("kind"), kind)
        }
    }

    func encodeLeaderboardWindow(_ value: LeaderboardWindowType) -> JSONValue {
        switch value {
        case .hourly: return kindNode("hourly")
        case .daily: return kindNode("daily")
        case .weekly: return kindNode("weekly")
        case .monthly: return kindNode("monthly")
        case .custom(let duration):
            return .object([
                ("kind", .string("custom")),
                ("durationBits", .string(hex(duration.bitPattern, digits: 16))),
            ])
        }
    }

    func decodeLeaderboardWindow(
        _ node: JSONValue,
        path: String
    ) throws -> LeaderboardWindowType {
        let object = try JSONObject(node, path: path)
        let kind = try object.required("kind").string(path: object.child("kind"))
        switch kind {
        case "hourly": try object.validateKeys(["kind"]); return .hourly
        case "daily": try object.validateKeys(["kind"]); return .daily
        case "weekly": try object.validateKeys(["kind"]); return .weekly
        case "monthly": try object.validateKeys(["kind"]); return .monthly
        case "custom":
            try object.validateKeys(["kind", "durationBits"])
            let bits: UInt64 = try decodeHex(
                object.required("durationBits").string(path: object.child("durationBits")),
                digits: 16,
                path: object.child("durationBits")
            )
            let duration = Double(bitPattern: bits)
            guard duration.isFinite else {
                throw SchemaJSONError.invalidValue(
                    path: object.child("durationBits"),
                    reason: "non-finite duration"
                )
            }
            return .custom(duration: duration)
        default: throw invalidEnum(object.child("kind"), kind)
        }
    }

    func encodePermutation(_ value: PermutationPattern) -> JSONValue {
        switch value {
        case .identity(let size):
            return .object([
                ("kind", .string("identity")),
                ("size", .number(String(size))),
            ])
        case .swapping(let first, let second, let size):
            return .object([
                ("kind", .string("swapping")),
                ("first", .number(String(first))),
                ("second", .number(String(second))),
                ("size", .number(String(size))),
            ])
        case .ordering(let indices):
            return .object([
                ("kind", .string("ordering")),
                ("indices", .array(indices.map { .number(String($0)) })),
            ])
        }
    }

    func decodePermutation(
        _ node: JSONValue,
        path: String
    ) throws -> PermutationPattern {
        let object = try JSONObject(node, path: path)
        let kind = try object.required("kind").string(path: object.child("kind"))
        switch kind {
        case "identity":
            try object.validateKeys(["kind", "size"])
            return .identity(size: try integer(object, "size"))
        case "swapping":
            try object.validateKeys(["kind", "first", "second", "size"])
            return .swapping(
                try integer(object, "first"),
                try integer(object, "second"),
                size: try integer(object, "size")
            )
        case "ordering":
            try object.validateKeys(["kind", "indices"])
            let values = try object.required("indices").array(path: object.child("indices"))
            return .ordering(
                try values.enumerated().map {
                    try integer(
                        $0.element,
                        path: "\(object.child("indices"))[\($0.offset)]"
                    )
                }
            )
        default: throw invalidEnum(object.child("kind"), kind)
        }
    }

    func kindNode(_ name: String) -> JSONValue {
        .object([("kind", .string(name))])
    }

    func hex<T: FixedWidthInteger>(_ value: T, digits: Int) -> String {
        let raw = String(value, radix: 16, uppercase: false)
        return String(repeating: "0", count: digits - raw.count) + raw
    }

    func decodeHex<T: FixedWidthInteger>(
        _ value: String,
        digits: Int,
        path: String
    ) throws -> T {
        guard value.utf8.count == digits,
              value.utf8.allSatisfy({
                  (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
              }),
              let decoded = T(value, radix: 16) else {
            throw SchemaJSONError.invalidValue(
                path: path,
                reason: "invalid fixed-width bit pattern"
            )
        }
        return decoded
    }

    func invalidEnum(_ path: String, _ value: String) -> SchemaJSONError {
        .invalidValue(path: path, reason: "unknown value '\(value)'")
    }
}
