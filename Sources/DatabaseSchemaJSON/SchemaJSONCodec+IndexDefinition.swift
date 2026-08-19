import DatabaseKit

extension SchemaJSONCodec {
    func encodeIndexDeclaration<FieldReference>(
        _ value: IndexDeclaration<FieldReference>,
        encodeField: (FieldReference) throws -> JSONValue
    ) throws -> JSONValue {
        .object([
            ("name", .string(value.name)),
            (
                "definition",
                try encodeIndexDefinition(
                    value.definition,
                    encodeField: encodeField
                )
            ),
        ])
    }

    func encodeIndexDefinition<FieldReference>(
        _ value: IndexDefinition<FieldReference>,
        encodeField: (FieldReference) throws -> JSONValue
    ) throws -> JSONValue {
        switch value {
        case .ordered(let keys, let includedFields, let unique):
            return .object([
                ("kind", .string("ordered")),
                ("keys", try encodeIndexKeys(keys, encodeField: encodeField)),
                (
                    "includedFields",
                    .array(try includedFields.map(encodeField))
                ),
                ("unique", .bool(unique)),
            ])
        case .aggregate(let function, let groupBy, let field):
            return .object([
                ("kind", .string("aggregate")),
                ("function", encodeAggregateFunction(function)),
                ("groupBy", try encodeIndexKeys(groupBy, encodeField: encodeField)),
                ("field", try field.map(encodeField) ?? .null),
            ])
        case .updateCount(let field):
            return .object([
                ("kind", .string("updateCount")),
                ("field", try encodeField(field)),
            ])
        case .history(let version, let retention):
            return .object([
                ("kind", .string("history")),
                ("version", try encodeField(version)),
                ("retention", encodeVersionStrategy(retention)),
            ])
        case .bitmap(let field):
            return .object([
                ("kind", .string("bitmap")),
                ("field", try encodeField(field)),
            ])
        case .leaderboard(let groupBy, let score, let window, let windowCount):
            return .object([
                ("kind", .string("leaderboard")),
                ("groupBy", try encodeIndexKeys(groupBy, encodeField: encodeField)),
                ("score", try encodeField(score)),
                ("window", encodeLeaderboardWindow(window)),
                ("windowCount", .number(String(windowCount))),
            ])
        case .vector(let embedding, let dimensions, let metric):
            return .object([
                ("kind", .string("vector")),
                ("embedding", try encodeField(embedding)),
                ("dimensions", .number(String(dimensions))),
                ("metric", .string(metric.rawValue)),
            ])
        case .text(let fields, let mode):
            return .object([
                ("kind", .string("text")),
                ("fields", .array(try fields.map(encodeField))),
                ("mode", encodeTextMode(mode)),
            ])
        case .spatial(let location, let encoding, let level):
            return .object([
                ("kind", .string("spatial")),
                ("location", try encodeField(location)),
                ("encoding", .string(encoding.rawValue)),
                ("level", .number(String(level))),
            ])
        case .rank(let score):
            return .object([
                ("kind", .string("rank")),
                ("score", try encodeField(score)),
            ])
        case .graph(let graph, let includedFields):
            return try encodeGraphIndex(
                graph,
                includedFields: includedFields,
                encodeField: encodeField
            )
        case .custom(let custom):
            return .object([
                ("kind", .string("custom")),
                ("identifier", .string(custom.identifier)),
                (
                    "keys",
                    try encodeIndexKeys(custom.keys, encodeField: encodeField)
                ),
                (
                    "includedFields",
                    .array(try custom.includedFields.map(encodeField))
                ),
                ("parameters", try encodeFieldValueMap(custom.parameters)),
            ])
        }
    }

    private func encodeIndexKeys<FieldReference>(
        _ keys: [IndexKey<FieldReference>],
        encodeField: (FieldReference) throws -> JSONValue
    ) throws -> JSONValue {
        .array(
            try keys.map { key in
                .object([
                    ("field", try encodeField(key.field)),
                    ("order", .string(key.order.rawValue)),
                ])
            }
        )
    }

    private func encodeAggregateFunction(
        _ function: AggregateIndexFunction
    ) -> JSONValue {
        switch function {
        case .count: return kindNode("count")
        case .sum: return kindNode("sum")
        case .minimum: return kindNode("minimum")
        case .maximum: return kindNode("maximum")
        case .average: return kindNode("average")
        case .nonNullCount: return kindNode("nonNullCount")
        case .approximateDistinct(let precision):
            return .object([
                ("kind", .string("approximateDistinct")),
                ("precision", .number(String(precision))),
            ])
        case .percentile(let compression):
            return .object([
                ("kind", .string("percentile")),
                (
                    "compressionBits",
                    .string(hex(compression.bitPattern, digits: 16))
                ),
            ])
        }
    }

    private func encodeTextMode(_ mode: TextIndexMode) -> JSONValue {
        switch mode {
        case .fullText(
            let tokenizer,
            let storePositions,
            let ngramSize,
            let minimumTermLength
        ):
            return .object([
                ("kind", .string("fullText")),
                ("tokenizer", .string(tokenizer.rawValue)),
                ("storePositions", .bool(storePositions)),
                ("ngramSize", .number(String(ngramSize))),
                ("minimumTermLength", .number(String(minimumTermLength))),
            ])
        case .autocomplete(
            let minimumPrefixLength,
            let maximumPrefixLength
        ):
            return .object([
                ("kind", .string("autocomplete")),
                ("minimumPrefixLength", .number(String(minimumPrefixLength))),
                ("maximumPrefixLength", .number(String(maximumPrefixLength))),
            ])
        }
    }

    private func encodeGraphIndex<FieldReference>(
        _ graph: GraphIndexDefinition<FieldReference>,
        includedFields: [FieldReference],
        encodeField: (FieldReference) throws -> JSONValue
    ) throws -> JSONValue {
        switch graph {
        case .property(let source, let label, let target, let graph, let strategy):
            let encodedLabel: JSONValue
            switch label {
            case .field(let field):
                encodedLabel = .object([
                    ("kind", .string("field")),
                    ("field", try encodeField(field)),
                ])
            case .implicit:
                encodedLabel = kindNode("implicit")
            }
            return .object([
                ("kind", .string("graph")),
                ("representation", .string("property")),
                ("source", try encodeField(source)),
                ("label", encodedLabel),
                ("target", try encodeField(target)),
                ("graph", try graph.map(encodeField) ?? .null),
                ("strategy", .string(strategy.rawValue)),
                ("includedFields", .array(try includedFields.map(encodeField))),
            ])
        case .rdf(let subject, let predicate, let object, let graph):
            return .object([
                ("kind", .string("graph")),
                ("representation", .string("rdf")),
                ("subject", try encodeField(subject)),
                ("predicate", try encodeField(predicate)),
                ("object", try encodeField(object)),
                ("graph", try graph.map(encodeField) ?? .null),
                ("includedFields", .array(try includedFields.map(encodeField))),
            ])
        case .ontologyProjection(let individualIRIBase, let graph):
            return .object([
                ("kind", .string("graph")),
                ("representation", .string("ontologyProjection")),
                ("individualIRIBase", .string(individualIRIBase)),
                (
                    "graph",
                    try graph.map {
                        try fieldValueCodec.encode(.rdfTerm($0.term))
                    } ?? .null
                ),
                ("includedFields", .array(try includedFields.map(encodeField))),
            ])
        }
    }
}

extension SchemaJSONCodec {
    func decodeIndexDeclaration<FieldReference>(
        _ node: JSONValue,
        path: String,
        decodeField: (JSONValue, String) throws -> FieldReference
    ) throws -> IndexDeclaration<FieldReference> {
        let object = try JSONObject(node, path: path)
        try object.validateKeys(["name", "definition"])
        return IndexDeclaration(
            name: try object.required("name").string(path: object.child("name")),
            definition: try decodeIndexDefinition(
                object.required("definition"),
                path: object.child("definition"),
                decodeField: decodeField
            )
        )
    }

    func decodeIndexDefinition<FieldReference>(
        _ node: JSONValue,
        path: String,
        decodeField: (JSONValue, String) throws -> FieldReference
    ) throws -> IndexDefinition<FieldReference> {
        let object = try JSONObject(node, path: path)
        let kind = try object.required("kind").string(path: object.child("kind"))
        switch kind {
        case "ordered":
            try object.validateKeys(["kind", "keys", "includedFields", "unique"])
            return .ordered(
                keys: try decodeIndexKeys(
                    object.required("keys"),
                    path: object.child("keys"),
                    decodeField: decodeField
                ),
                includedFields: try decodeIndexFields(
                    object.required("includedFields"),
                    path: object.child("includedFields"),
                    decodeField: decodeField
                ),
                unique: try object.required("unique").bool(
                    path: object.child("unique")
                )
            )
        case "aggregate":
            try object.validateKeys(["kind", "function", "groupBy", "field"])
            return .aggregate(
                function: try decodeAggregateFunction(
                    object.required("function"),
                    path: object.child("function")
                ),
                groupBy: try decodeIndexKeys(
                    object.required("groupBy"),
                    path: object.child("groupBy"),
                    decodeField: decodeField
                ),
                value: try decodeOptionalIndexField(
                    object.required("field"),
                    path: object.child("field"),
                    decodeField: decodeField
                )
            )
        case "updateCount":
            try object.validateKeys(["kind", "field"])
            return .updateCount(
                field: try decodeField(
                    object.required("field"),
                    object.child("field")
                )
            )
        case "history":
            try object.validateKeys(["kind", "version", "retention"])
            return .history(
                version: try decodeField(
                    object.required("version"),
                    object.child("version")
                ),
                retention: try decodeVersionStrategy(
                    object.required("retention"),
                    path: object.child("retention")
                )
            )
        case "bitmap":
            try object.validateKeys(["kind", "field"])
            return .bitmap(
                field: try decodeField(
                    object.required("field"),
                    object.child("field")
                )
            )
        case "leaderboard":
            try object.validateKeys([
                "kind", "groupBy", "score", "window", "windowCount",
            ])
            return .leaderboard(
                groupBy: try decodeIndexKeys(
                    object.required("groupBy"),
                    path: object.child("groupBy"),
                    decodeField: decodeField
                ),
                score: try decodeField(
                    object.required("score"),
                    object.child("score")
                ),
                window: try decodeLeaderboardWindow(
                    object.required("window"),
                    path: object.child("window")
                ),
                windowCount: try integer(object, "windowCount")
            )
        case "vector":
            try object.validateKeys([
                "kind", "embedding", "dimensions", "metric",
            ])
            let rawMetric = try object.required("metric").string(
                path: object.child("metric")
            )
            guard let metric = VectorMetric(rawValue: rawMetric) else {
                throw invalidEnum(object.child("metric"), rawMetric)
            }
            return .vector(
                embedding: try decodeField(
                    object.required("embedding"),
                    object.child("embedding")
                ),
                dimensions: try integer(object, "dimensions"),
                metric: metric
            )
        case "text":
            try object.validateKeys(["kind", "fields", "mode"])
            return .text(
                fields: try decodeIndexFields(
                    object.required("fields"),
                    path: object.child("fields"),
                    decodeField: decodeField
                ),
                mode: try decodeTextMode(
                    object.required("mode"),
                    path: object.child("mode")
                )
            )
        case "spatial":
            try object.validateKeys(["kind", "location", "encoding", "level"])
            let rawEncoding = try object.required("encoding").string(
                path: object.child("encoding")
            )
            guard let encoding = SpatialEncoding(rawValue: rawEncoding) else {
                throw invalidEnum(object.child("encoding"), rawEncoding)
            }
            return .spatial(
                location: try decodeField(
                    object.required("location"),
                    object.child("location")
                ),
                encoding: encoding,
                level: try integer(object, "level")
            )
        case "rank":
            try object.validateKeys(["kind", "score"])
            return .rank(
                score: try decodeField(
                    object.required("score"),
                    object.child("score")
                )
            )
        case "graph":
            return try decodeGraphIndex(
                object,
                decodeField: decodeField
            )
        case "custom":
            try object.validateKeys([
                "kind", "identifier", "keys", "includedFields", "parameters",
            ])
            return .custom(
                CustomIndexDefinition(
                    identifier: try object.required("identifier").string(
                        path: object.child("identifier")
                    ),
                    keys: try decodeIndexKeys(
                        object.required("keys"),
                        path: object.child("keys"),
                        decodeField: decodeField
                    ),
                    includedFields: try decodeIndexFields(
                        object.required("includedFields"),
                        path: object.child("includedFields"),
                        decodeField: decodeField
                    ),
                    parameters: try decodeFieldValueMap(
                        object.required("parameters"),
                        path: object.child("parameters")
                    )
                )
            )
        default:
            throw SchemaJSONError.invalidValue(
                path: object.child("kind"),
                reason: "unknown index definition '\(kind)'"
            )
        }
    }

    private func decodeIndexKeys<FieldReference>(
        _ node: JSONValue,
        path: String,
        decodeField: (JSONValue, String) throws -> FieldReference
    ) throws -> [IndexKey<FieldReference>] {
        let nodes = try node.array(path: path)
        try requireCollection(nodes.count, path: path)
        return try nodes.enumerated().map { offset, node in
            let keyPath = "\(path)[\(offset)]"
            let object = try JSONObject(node, path: keyPath)
            try object.validateKeys(["field", "order"])
            let rawOrder = try object.required("order").string(
                path: object.child("order")
            )
            guard let order = IndexFieldOrder(rawValue: rawOrder) else {
                throw invalidEnum(object.child("order"), rawOrder)
            }
            return IndexKey(
                try decodeField(
                    object.required("field"),
                    object.child("field")
                ),
                order: order
            )
        }
    }

    private func decodeIndexFields<FieldReference>(
        _ node: JSONValue,
        path: String,
        decodeField: (JSONValue, String) throws -> FieldReference
    ) throws -> [FieldReference] {
        let nodes = try node.array(path: path)
        try requireCollection(nodes.count, path: path)
        return try nodes.enumerated().map {
            try decodeField($0.element, "\(path)[\($0.offset)]")
        }
    }

    private func decodeOptionalIndexField<FieldReference>(
        _ node: JSONValue,
        path: String,
        decodeField: (JSONValue, String) throws -> FieldReference
    ) throws -> FieldReference? {
        guard case .null = node else {
            return try decodeField(node, path)
        }
        return nil
    }

    private func decodeAggregateFunction(
        _ node: JSONValue,
        path: String
    ) throws -> AggregateIndexFunction {
        let object = try JSONObject(node, path: path)
        let kind = try object.required("kind").string(path: object.child("kind"))
        switch kind {
        case "count": try object.validateKeys(["kind"]); return .count
        case "sum": try object.validateKeys(["kind"]); return .sum
        case "minimum": try object.validateKeys(["kind"]); return .minimum
        case "maximum": try object.validateKeys(["kind"]); return .maximum
        case "average": try object.validateKeys(["kind"]); return .average
        case "nonNullCount":
            try object.validateKeys(["kind"])
            return .nonNullCount
        case "approximateDistinct":
            try object.validateKeys(["kind", "precision"])
            return .approximateDistinct(
                precision: try integer(object, "precision")
            )
        case "percentile":
            try object.validateKeys(["kind", "compressionBits"])
            let bits: UInt64 = try decodeHex(
                object.required("compressionBits").string(
                    path: object.child("compressionBits")
                ),
                digits: 16,
                path: object.child("compressionBits")
            )
            let compression = Double(bitPattern: bits)
            guard compression.isFinite else {
                throw SchemaJSONError.invalidValue(
                    path: object.child("compressionBits"),
                    reason: "non-finite percentile compression"
                )
            }
            return .percentile(compression: compression)
        default:
            throw invalidEnum(object.child("kind"), kind)
        }
    }

    private func decodeTextMode(
        _ node: JSONValue,
        path: String
    ) throws -> TextIndexMode {
        let object = try JSONObject(node, path: path)
        let kind = try object.required("kind").string(path: object.child("kind"))
        switch kind {
        case "fullText":
            try object.validateKeys([
                "kind", "tokenizer", "storePositions", "ngramSize",
                "minimumTermLength",
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
                minimumTermLength: try integer(object, "minimumTermLength")
            )
        case "autocomplete":
            try object.validateKeys([
                "kind", "minimumPrefixLength", "maximumPrefixLength",
            ])
            return .autocomplete(
                minimumPrefixLength: try integer(
                    object,
                    "minimumPrefixLength"
                ),
                maximumPrefixLength: try integer(
                    object,
                    "maximumPrefixLength"
                )
            )
        default:
            throw invalidEnum(object.child("kind"), kind)
        }
    }

    private func decodeGraphIndex<FieldReference>(
        _ object: JSONObject,
        decodeField: (JSONValue, String) throws -> FieldReference
    ) throws -> IndexDefinition<FieldReference> {
        let representation = try object.required("representation").string(
            path: object.child("representation")
        )
        switch representation {
        case "property":
            try object.validateKeys([
                "kind", "representation", "source", "label", "target",
                "graph", "strategy", "includedFields",
            ])
            let labelObject = try JSONObject(
                object.required("label"),
                path: object.child("label")
            )
            let labelKind = try labelObject.required("kind").string(
                path: labelObject.child("kind")
            )
            let label: PropertyGraphLabel<FieldReference>
            switch labelKind {
            case "field":
                try labelObject.validateKeys(["kind", "field"])
                label = .field(
                    try decodeField(
                        labelObject.required("field"),
                        labelObject.child("field")
                    )
                )
            case "implicit":
                try labelObject.validateKeys(["kind"])
                label = .implicit
            default:
                throw invalidEnum(labelObject.child("kind"), labelKind)
            }
            let rawStrategy = try object.required("strategy").string(
                path: object.child("strategy")
            )
            guard let strategy = PropertyGraphIndexStrategy(
                rawValue: rawStrategy
            ) else {
                throw invalidEnum(object.child("strategy"), rawStrategy)
            }
            return .graph(
                .property(
                    source: try decodeField(
                        object.required("source"),
                        object.child("source")
                    ),
                    label: label,
                    target: try decodeField(
                        object.required("target"),
                        object.child("target")
                    ),
                    graph: try decodeOptionalIndexField(
                        object.required("graph"),
                        path: object.child("graph"),
                        decodeField: decodeField
                    ),
                    strategy: strategy
                ),
                includedFields: try decodeIndexFields(
                    object.required("includedFields"),
                    path: object.child("includedFields"),
                    decodeField: decodeField
                )
            )
        case "rdf":
            try object.validateKeys([
                "kind", "representation", "subject", "predicate", "object",
                "graph", "includedFields",
            ])
            return .graph(
                .rdf(
                    subject: try decodeField(
                        object.required("subject"),
                        object.child("subject")
                    ),
                    predicate: try decodeField(
                        object.required("predicate"),
                        object.child("predicate")
                    ),
                    object: try decodeField(
                        object.required("object"),
                        object.child("object")
                    ),
                    graph: try decodeOptionalIndexField(
                        object.required("graph"),
                        path: object.child("graph"),
                        decodeField: decodeField
                    )
                ),
                includedFields: try decodeIndexFields(
                    object.required("includedFields"),
                    path: object.child("includedFields"),
                    decodeField: decodeField
                )
            )
        case "ontologyProjection":
            try object.validateKeys([
                "kind", "representation", "individualIRIBase", "graph",
                "includedFields",
            ])
            let graphNode = try object.required("graph")
            let graph: RDFGraphName?
            if case .null = graphNode {
                graph = nil
            } else {
                let value = try fieldValueCodec.decode(
                    graphNode,
                    path: object.child("graph")
                )
                guard case .rdfTerm(let term) = value else {
                    throw SchemaJSONError.invalidValue(
                        path: object.child("graph"),
                        reason: "ontology graph must be an RDF term"
                    )
                }
                do {
                    graph = try RDFGraphName(term)
                } catch {
                    throw SchemaJSONError.invalidValue(
                        path: object.child("graph"),
                        reason: "invalid RDF graph name"
                    )
                }
            }
            return .graph(
                .ontologyProjection(
                    individualIRIBase: try object.required("individualIRIBase")
                        .string(path: object.child("individualIRIBase")),
                    graph: graph
                ),
                includedFields: try decodeIndexFields(
                    object.required("includedFields"),
                    path: object.child("includedFields"),
                    decodeField: decodeField
                )
            )
        default:
            throw invalidEnum(object.child("representation"), representation)
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
                object.required("durationBits").string(
                    path: object.child("durationBits")
                ),
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
