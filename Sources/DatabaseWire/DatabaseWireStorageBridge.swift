public enum DatabaseWireStorageBridge {
    public static func schemaKey() -> [UInt8] {
        [0x5F, 0x73, 0x63, 0x68, 0x65, 0x6D, 0x61]
    }

    public static func schemaSetOperation(
        _ schema: DatabaseWireSchema
    ) throws(DatabaseWireError) -> DatabaseWireKeyValueOperation {
        .set(
            key: schemaKey(),
            value: try DatabaseWireCodec.encode(schema: schema)
        )
    }

    public static func recordPrefix(
        entityName: String
    ) throws(DatabaseWireError) -> [UInt8] {
        var writer = DatabaseWireBinaryWriter()
        writer.writeUInt8(0x52)
        try writer.writeString(entityName)
        return writer.bytes
    }

    public static func recordKey(
        entityName: String,
        id: String
    ) throws(DatabaseWireError) -> [UInt8] {
        var key = try recordPrefix(entityName: entityName)
        var writer = DatabaseWireBinaryWriter()
        try writer.writeString(id)
        key.append(contentsOf: writer.bytes)
        return key
    }

    public static func recordSetOperation(
        _ record: DatabaseWireRecord
    ) throws(DatabaseWireError) -> DatabaseWireKeyValueOperation {
        .set(
            key: try recordKey(entityName: record.typeName, id: record.id),
            value: try DatabaseWireCodec.encode(record: record)
        )
    }

    public static func recordLookupOperation(
        entityName: String,
        id: String
    ) throws(DatabaseWireError) -> DatabaseWireKeyValueOperation {
        .get(key: try recordKey(entityName: entityName, id: id))
    }

    public static func entityScanOperation(
        entityName: String,
        limit: Int = 0,
        reverse: Bool = false
    ) throws(DatabaseWireError) -> DatabaseWireKeyValueOperation {
        let begin = try recordPrefix(entityName: entityName)
        return .range(
            begin: begin,
            end: nextPrefix(after: begin),
            limit: limit,
            reverse: reverse
        )
    }

    public static func queryOperation(
        _ query: DatabaseWireQueryRequest
    ) throws(DatabaseWireError) -> DatabaseWireKeyValueOperation {
        guard query.predicate == nil else {
            throw .unsupportedPredicatePlan
        }
        return try entityScanOperation(
            entityName: query.typeName,
            limit: limitValue(query.limit),
            reverse: false
        )
    }

    public static func queryPlan(
        _ query: DatabaseWireQueryRequest
    ) throws(DatabaseWireError) -> DatabaseWireQueryPlan {
        try DatabaseWireQueryPlan(
            operation: entityScanOperation(
                entityName: query.typeName,
                limit: query.predicate == nil ? limitValue(query.limit) : 0,
                reverse: false
            ),
            postFilter: query.predicate
        )
    }

    public static func decodeRecordValue(
        _ value: [UInt8]
    ) throws(DatabaseWireError) -> DatabaseWireRecord {
        try DatabaseWireCodec.decodeRecord(value)
    }

    private static func nextPrefix(after prefix: [UInt8]) -> [UInt8] {
        var end = prefix
        var index = end.count
        while index > 0 {
            index -= 1
            if end[index] != 0xFF {
                end[index] += 1
                return Array(end.prefix(index + 1))
            }
        }
        return prefix + [0x00]
    }

    private static func limitValue(_ value: UInt32) throws(DatabaseWireError) -> Int {
        guard UInt64(value) <= UInt64(Int.max) else {
            throw DatabaseWireError.byteCountOverflow
        }
        return Int(value)
    }
}
