// StandardIndexKinds.swift
// FDBModel - Standard IndexKind implementations (FDB-independent)
//
// These implementations are FDB-independent and can be used across all platforms.
// They are automatically available when importing FDBModel.

#if canImport(Foundation)
import struct Foundation.TimeInterval
#else
public typealias TimeInterval = Double
#endif

// MARK: - ScalarIndexKind

/// Standard VALUE index for sorting and range queries
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Product {
///     #Index(type: ScalarIndexKind<Product>(fields: [\.category, \.price]))
///     var category: String
///     var price: Int
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][field1Value][field2Value]...[primaryKey] = ''`
///
/// **Supports**:
/// - Exact match queries
/// - Range queries (WHERE price >= 100)
/// - Prefix queries
/// - Composite indexes
/// - Unique constraints
public struct ScalarIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "scalar" }
    public static var subspaceStructure: SubspaceStructure { .flat }

    /// Field names for this index (stored as strings for Codable)
    public let fieldNames: [String]

    /// Default index name: "{TypeName}_{field1}_{field2}_..."
    public var indexName: String {
        let flattenedNames = fieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        return "\(Root.persistableType)_\(flattenedNames.joined(separator: "_"))"
    }

    /// Initialize with KeyPaths (converted to field names internally)
    ///
    /// - Parameter fields: KeyPaths to indexed fields
    public init(fields: [PartialKeyPath<Root>]) {
        self.fieldNames = fields.map { Root.fieldName(for: $0) }
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(fieldNames: [String]) {
        self.fieldNames = fieldNames
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard !types.isEmpty else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 1,
                actual: 0
            )
        }
        for type in types {
            guard TypeValidation.isComparable(type) else {
                throw IndexTypeValidationError.unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "Scalar index requires Comparable types"
                )
            }
        }
    }
}

// MARK: - CountIndexKind

/// Aggregation index for counting records by grouping fields
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Order {
///     #Index(type: CountIndexKind<Order>(groupBy: [\.status, \.type]))
///     var status: String
///     var type: String
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][groupKey1][groupKey2]... = Int64(count)`
///
/// **Supports**:
/// - Get count by group key
/// - Atomic increment/decrement on insert/delete
/// - Multiple grouping fields
public struct CountIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "count" }
    public static var subspaceStructure: SubspaceStructure { .aggregation }

    /// Field names for grouping (stored as strings for Codable)
    public let fieldNames: [String]

    /// Default index name: "{TypeName}_count_{field1}_{field2}_..."
    public var indexName: String {
        let flattenedNames = fieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        return "\(Root.persistableType)_count_\(flattenedNames.joined(separator: "_"))"
    }

    /// Initialize with KeyPaths (converted to field names internally)
    ///
    /// - Parameter groupBy: KeyPaths to grouping fields
    public init(groupBy: [PartialKeyPath<Root>]) {
        self.fieldNames = groupBy.map { Root.fieldName(for: $0) }
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(fieldNames: [String]) {
        self.fieldNames = fieldNames
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard !types.isEmpty else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 1,
                actual: 0
            )
        }
        for type in types {
            guard TypeValidation.isComparable(type) else {
                throw IndexTypeValidationError.unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "Count index grouping fields must be Comparable"
                )
            }
        }
    }
}

// MARK: - SumIndexKind

/// Aggregation index for summing numeric values by grouping fields
///
/// **Type-Safe Design**: The `Value` type parameter preserves numeric type information,
/// ensuring integers remain integers and floating-point types use appropriate storage.
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Order {
///     var customerId: String
///     var amount: Int64  // Type preserved as Int64
///
///     #Index<Order>(type: SumIndexKind(groupBy: [\.customerId], value: \.amount))
///     // Infers: SumIndexKind<Order, Int64>
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][groupKey1][groupKey2]... = Value(sum)`
///
/// **Storage**:
/// - Integer types (Int, Int64, Int32): Stored as Int64 bytes
/// - Floating-point types (Float, Double): Stored as scaled fixed-point Int64
///
/// **Supports**:
/// - Get sum by group key
/// - Atomic add/subtract on insert/update/delete
/// - Multiple grouping fields
/// - Precision preservation for integer types
public struct SumIndexKind<Root: Persistable, Value: Numeric & Codable & Sendable>: IndexKind {
    public static var identifier: String { "sum" }
    public static var subspaceStructure: SubspaceStructure { .aggregation }

    /// Field names for grouping
    public let groupByFieldNames: [String]

    /// Field name for the value to sum
    public let valueFieldName: String

    /// Value type name for Codable reconstruction
    public let valueTypeName: String

    /// All field names (groupBy + value) for IndexKind protocol
    public var fieldNames: [String] {
        groupByFieldNames + [valueFieldName]
    }

    /// Default index name: "{TypeName}_sum_{groupField1}_{valueField}"
    public var indexName: String {
        let groupNames = groupByFieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        let valueName = valueFieldName.replacingOccurrences(of: ".", with: "_")
        if groupNames.isEmpty {
            return "\(Root.persistableType)_sum_\(valueName)"
        }
        return "\(Root.persistableType)_sum_\(groupNames.joined(separator: "_"))_\(valueName)"
    }

    /// Initialize with KeyPaths - type is inferred from KeyPath
    ///
    /// - Parameters:
    ///   - groupBy: KeyPaths to grouping fields
    ///   - value: KeyPath to the numeric field to sum (type inferred)
    public init(groupBy: [PartialKeyPath<Root>], value: KeyPath<Root, Value>) {
        self.groupByFieldNames = groupBy.map { Root.fieldName(for: $0) }
        self.valueFieldName = Root.fieldName(for: value)
        self.valueTypeName = String(describing: Value.self)
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(groupByFieldNames: [String], valueFieldName: String, valueTypeName: String) {
        self.groupByFieldNames = groupByFieldNames
        self.valueFieldName = valueFieldName
        self.valueTypeName = valueTypeName
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.count >= 2 else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 2,
                actual: types.count
            )
        }
        let groupingTypes = types.dropLast()
        for type in groupingTypes {
            guard TypeValidation.isComparable(type) else {
                throw IndexTypeValidationError.unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "Sum index grouping fields must be Comparable"
                )
            }
        }
        guard let valueType = types.last else { return }
        guard TypeValidation.isNumeric(valueType) else {
            throw IndexTypeValidationError.unsupportedType(
                index: identifier,
                type: valueType,
                reason: "Sum index value field must be Numeric"
            )
        }
    }
}

// MARK: - MinIndexKind

/// Aggregation index for tracking minimum values by grouping fields
///
/// **Type-Safe Design**: The `Value` type parameter preserves the value type,
/// ensuring the minimum is returned in its original type.
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Product {
///     var category: String
///     var price: Int64  // Type preserved as Int64
///
///     #Index<Product>(type: MinIndexKind(groupBy: [\.category], value: \.price))
///     // Infers: MinIndexKind<Product, Int64>
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][groupKey][value][primaryKey] = ''`
///
/// **Supports**:
/// - Get minimum value by group key
/// - Efficient min tracking via sorted storage
/// - Type preservation for result
public struct MinIndexKind<Root: Persistable, Value: Comparable & Codable & Sendable>: IndexKind {
    public static var identifier: String { "min" }
    public static var subspaceStructure: SubspaceStructure { .flat }

    /// Field names for grouping
    public let groupByFieldNames: [String]

    /// Field name for the value to track minimum
    public let valueFieldName: String

    /// Value type name for Codable reconstruction
    public let valueTypeName: String

    /// All field names (groupBy + value) for IndexKind protocol
    public var fieldNames: [String] {
        groupByFieldNames + [valueFieldName]
    }

    /// Default index name: "{TypeName}_min_{groupField1}_{valueField}"
    public var indexName: String {
        let groupNames = groupByFieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        let valueName = valueFieldName.replacingOccurrences(of: ".", with: "_")
        if groupNames.isEmpty {
            return "\(Root.persistableType)_min_\(valueName)"
        }
        return "\(Root.persistableType)_min_\(groupNames.joined(separator: "_"))_\(valueName)"
    }

    /// Initialize with KeyPaths - type is inferred from KeyPath
    public init(groupBy: [PartialKeyPath<Root>], value: KeyPath<Root, Value>) {
        self.groupByFieldNames = groupBy.map { Root.fieldName(for: $0) }
        self.valueFieldName = Root.fieldName(for: value)
        self.valueTypeName = String(describing: Value.self)
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(groupByFieldNames: [String], valueFieldName: String, valueTypeName: String) {
        self.groupByFieldNames = groupByFieldNames
        self.valueFieldName = valueFieldName
        self.valueTypeName = valueTypeName
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.count >= 2 else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 2,
                actual: types.count
            )
        }
        for type in types {
            guard TypeValidation.isComparable(type) else {
                throw IndexTypeValidationError.unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "Min index requires all fields to be Comparable"
                )
            }
        }
    }
}

// MARK: - MaxIndexKind

/// Aggregation index for tracking maximum values by grouping fields
///
/// **Type-Safe Design**: The `Value` type parameter preserves the value type,
/// ensuring the maximum is returned in its original type.
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Product {
///     var category: String
///     var price: Int64  // Type preserved as Int64
///
///     #Index<Product>(type: MaxIndexKind(groupBy: [\.category], value: \.price))
///     // Infers: MaxIndexKind<Product, Int64>
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][groupKey][value][primaryKey] = ''`
///
/// **Supports**:
/// - Get maximum value by group key
/// - Efficient max tracking via reverse-sorted storage
/// - Type preservation for result
public struct MaxIndexKind<Root: Persistable, Value: Comparable & Codable & Sendable>: IndexKind {
    public static var identifier: String { "max" }
    public static var subspaceStructure: SubspaceStructure { .flat }

    /// Field names for grouping
    public let groupByFieldNames: [String]

    /// Field name for the value to track maximum
    public let valueFieldName: String

    /// Value type name for Codable reconstruction
    public let valueTypeName: String

    /// All field names (groupBy + value) for IndexKind protocol
    public var fieldNames: [String] {
        groupByFieldNames + [valueFieldName]
    }

    /// Default index name: "{TypeName}_max_{groupField1}_{valueField}"
    public var indexName: String {
        let groupNames = groupByFieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        let valueName = valueFieldName.replacingOccurrences(of: ".", with: "_")
        if groupNames.isEmpty {
            return "\(Root.persistableType)_max_\(valueName)"
        }
        return "\(Root.persistableType)_max_\(groupNames.joined(separator: "_"))_\(valueName)"
    }

    /// Initialize with KeyPaths - type is inferred from KeyPath
    public init(groupBy: [PartialKeyPath<Root>], value: KeyPath<Root, Value>) {
        self.groupByFieldNames = groupBy.map { Root.fieldName(for: $0) }
        self.valueFieldName = Root.fieldName(for: value)
        self.valueTypeName = String(describing: Value.self)
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(groupByFieldNames: [String], valueFieldName: String, valueTypeName: String) {
        self.groupByFieldNames = groupByFieldNames
        self.valueFieldName = valueFieldName
        self.valueTypeName = valueTypeName
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.count >= 2 else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 2,
                actual: types.count
            )
        }
        for type in types {
            guard TypeValidation.isComparable(type) else {
                throw IndexTypeValidationError.unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "Max index requires all fields to be Comparable"
                )
            }
        }
    }
}

// MARK: - AverageIndexKind

/// Aggregation index for computing average values by grouping fields
///
/// **Type-Safe Design**: The `Value` type parameter preserves the sum type,
/// while the result is always `Double` (since average = sum / count).
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Review {
///     var productID: Int64
///     var rating: Int64  // Rating * 100 (e.g., 4.5 stars = 450)
///
///     #Index<Review>(type: AverageIndexKind(groupBy: [\.productID], value: \.rating))
///     // Infers: AverageIndexKind<Review, Int64>
///     // Result type: Double (average = sum / count)
/// }
/// ```
///
/// **Key Structure**:
/// - `[indexSubspace][groupKey]["sum"] = Value (Int64 bytes or scaled Double)`
/// - `[indexSubspace][groupKey]["count"] = Int64`
///
/// **Storage**:
/// - Integer types (Int, Int64, Int32): Sum stored as Int64 bytes
/// - Floating-point types (Float, Double): Sum stored as scaled fixed-point Int64
///
/// **Result**: Always `Double` (average = sum / count)
///
/// **Supports**:
/// - Get average by group key
/// - Atomic increment/decrement on insert/update/delete
/// - Precision preservation for sum storage
public struct AverageIndexKind<Root: Persistable, Value: Numeric & Codable & Sendable>: IndexKind {
    public static var identifier: String { "average" }
    public static var subspaceStructure: SubspaceStructure { .aggregation }

    /// Field names for grouping
    public let groupByFieldNames: [String]

    /// Field name for the value to average
    public let valueFieldName: String

    /// Value type name for Codable reconstruction
    public let valueTypeName: String

    /// Result type is always Double (average = sum / count)
    public typealias ResultType = Double

    /// All field names (groupBy + value) for IndexKind protocol
    public var fieldNames: [String] {
        groupByFieldNames + [valueFieldName]
    }

    /// Default index name: "{TypeName}_avg_{groupField1}_{valueField}"
    public var indexName: String {
        let groupNames = groupByFieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        let valueName = valueFieldName.replacingOccurrences(of: ".", with: "_")
        if groupNames.isEmpty {
            return "\(Root.persistableType)_avg_\(valueName)"
        }
        return "\(Root.persistableType)_avg_\(groupNames.joined(separator: "_"))_\(valueName)"
    }

    /// Initialize with KeyPaths - type is inferred from KeyPath
    public init(groupBy: [PartialKeyPath<Root>], value: KeyPath<Root, Value>) {
        self.groupByFieldNames = groupBy.map { Root.fieldName(for: $0) }
        self.valueFieldName = Root.fieldName(for: value)
        self.valueTypeName = String(describing: Value.self)
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(groupByFieldNames: [String], valueFieldName: String, valueTypeName: String) {
        self.groupByFieldNames = groupByFieldNames
        self.valueFieldName = valueFieldName
        self.valueTypeName = valueTypeName
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.count >= 2 else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 2,
                actual: types.count
            )
        }
        let groupingTypes = types.dropLast()
        for type in groupingTypes {
            guard TypeValidation.isComparable(type) else {
                throw IndexTypeValidationError.unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "Average index grouping fields must be Comparable"
                )
            }
        }
        guard let valueType = types.last else { return }
        guard TypeValidation.isNumeric(valueType) else {
            throw IndexTypeValidationError.unsupportedType(
                index: identifier,
                type: valueType,
                reason: "Average index value field must be Numeric"
            )
        }
    }
}

// MARK: - VersionIndexKind

/// Version history retention strategy
///
/// **Strategies**:
/// - `.keepAll`: Keep all versions (unlimited history)
/// - `.keepLast(n)`: Keep only the last N versions
/// - `.keepForDuration(seconds)`: Keep versions for specific duration
public enum VersionHistoryStrategy: Sendable, Hashable, Codable {
    /// Keep all versions (unlimited history)
    case keepAll

    /// Keep only the last N versions
    case keepLast(Int)

    /// Keep versions for a specific duration (in seconds)
    case keepForDuration(TimeInterval)
}

/// Index for tracking record versions with history retention
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Document {
///     #Index(type: VersionIndexKind<Document>(field: \.id, strategy: .keepLast(10)))
///     var id: UUID
///     var title: String
///     var content: String
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][primaryKey][versionstamp] = data`
///
/// **Supports**:
/// - Version history tracking
/// - Point-in-time queries
/// - Rollback to previous versions
/// - Automatic cleanup based on retention strategy
public struct VersionIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "version" }
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    /// Field name for version tracking (typically the primary key)
    public let fieldNames: [String]

    /// Version history retention strategy
    public let strategy: VersionHistoryStrategy

    /// Default index name: "{TypeName}_version_{field}"
    public var indexName: String {
        let flattenedNames = fieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        return "\(Root.persistableType)_version_\(flattenedNames.joined(separator: "_"))"
    }

    /// Initialize with KeyPath
    ///
    /// - Parameters:
    ///   - field: KeyPath to the field for version tracking (typically id)
    ///   - strategy: Version history retention strategy (default: keepAll)
    public init(field: PartialKeyPath<Root>, strategy: VersionHistoryStrategy = .keepAll) {
        self.fieldNames = [Root.fieldName(for: field)]
        self.strategy = strategy
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(fieldNames: [String], strategy: VersionHistoryStrategy = .keepAll) {
        self.fieldNames = fieldNames
        self.strategy = strategy
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        // Version index accepts any types
    }
}

// MARK: - CountUpdatesIndexKind

/// Index for tracking the number of times each record has been updated
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Document {
///     #Index(type: CountUpdatesIndexKind<Document>(field: \.id))
///     var id: String
///     var content: String
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][primaryKey] = Int64(updateCount)`
///
/// **Supports**:
/// - Get update count for a specific record
/// - Atomic increment on each update
/// - Query records by update frequency
///
/// **Reference**: FDB Record Layer COUNT_UPDATES index type
public struct CountUpdatesIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "count_updates" }
    public static var subspaceStructure: SubspaceStructure { .flat }

    /// Field names (typically the primary key field)
    public let fieldNames: [String]

    /// Default index name: "{TypeName}_updates_{field}"
    public var indexName: String {
        let flattenedNames = fieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        return "\(Root.persistableType)_updates_\(flattenedNames.joined(separator: "_"))"
    }

    /// Initialize with KeyPath
    ///
    /// - Parameter field: KeyPath to the field (typically the primary key)
    public init(field: PartialKeyPath<Root>) {
        self.fieldNames = [Root.fieldName(for: field)]
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(fieldNames: [String]) {
        self.fieldNames = fieldNames
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard !types.isEmpty else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 1,
                actual: 0
            )
        }
    }
}

// MARK: - CountNotNullIndexKind

/// Aggregation index for counting records where a field is not null
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct User {
///     #Index(type: CountNotNullIndexKind<User>(groupBy: [\.country], value: \.phoneNumber))
///     var country: String
///     var phoneNumber: String?
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][groupKey1][groupKey2]... = Int64(nonNullCount)`
///
/// **Supports**:
/// - Count non-null values by group key
/// - Atomic increment/decrement on insert/update/delete
/// - Efficient null-value analytics
///
/// **Reference**: FDB Record Layer COUNT_NOT_NULL index type
public struct CountNotNullIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "count_not_null" }
    public static var subspaceStructure: SubspaceStructure { .aggregation }

    /// Field names for grouping
    public let groupByFieldNames: [String]

    /// Field name to check for null
    public let valueFieldName: String

    /// All field names (groupBy + value) for IndexKind protocol
    public var fieldNames: [String] {
        groupByFieldNames + [valueFieldName]
    }

    /// Default index name: "{TypeName}_notnull_{groupFields}_{valueField}"
    public var indexName: String {
        let groupNames = groupByFieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        let valueName = valueFieldName.replacingOccurrences(of: ".", with: "_")
        if groupNames.isEmpty {
            return "\(Root.persistableType)_notnull_\(valueName)"
        }
        return "\(Root.persistableType)_notnull_\(groupNames.joined(separator: "_"))_\(valueName)"
    }

    /// Initialize with KeyPaths
    ///
    /// - Parameters:
    ///   - groupBy: KeyPaths to grouping fields
    ///   - value: KeyPath to the field to check for null
    public init(groupBy: [PartialKeyPath<Root>], value: PartialKeyPath<Root>) {
        self.groupByFieldNames = groupBy.map { Root.fieldName(for: $0) }
        self.valueFieldName = Root.fieldName(for: value)
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(groupByFieldNames: [String], valueFieldName: String) {
        self.groupByFieldNames = groupByFieldNames
        self.valueFieldName = valueFieldName
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.count >= 1 else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 1,
                actual: 0
            )
        }
        let groupingTypes = types.dropLast()
        for type in groupingTypes {
            guard TypeValidation.isComparable(type) else {
                throw IndexTypeValidationError.unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "CountNotNull index grouping fields must be Comparable"
                )
            }
        }
    }
}

// MARK: - BitmapIndexKind

/// Bitmap index for efficient set operations on low-cardinality fields
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct User {
///     #Index(type: BitmapIndexKind<User>(field: \.status))
///     var status: String  // e.g., "active", "inactive", "pending"
/// }
/// ```
///
/// **Key Structure**: Uses Roaring Bitmap compression
/// ```
/// Key: [indexSubspace][fieldValue][containerIndex]
/// Value: Roaring bitmap container (array, bitmap, or run)
/// ```
///
/// **Supports**:
/// - Fast AND/OR/NOT operations on sets
/// - Efficient cardinality counting
/// - Low-cardinality field optimization
///
/// **Algorithm**: Roaring Bitmaps
/// Reference: Lemire et al., "Roaring Bitmaps: Implementation of an Optimized
/// Software Library", Software: Practice and Experience, 2016
///
/// **Best for**:
/// - Fields with <1000 distinct values
/// - Queries with multiple AND/OR conditions
/// - Aggregation queries
public struct BitmapIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "bitmap" }
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    /// Field names for this index
    public let fieldNames: [String]

    /// Default index name: "{TypeName}_bitmap_{field}"
    public var indexName: String {
        let flattenedNames = fieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        return "\(Root.persistableType)_bitmap_\(flattenedNames.joined(separator: "_"))"
    }

    /// Initialize with KeyPath
    ///
    /// - Parameter field: KeyPath to the low-cardinality field
    public init(field: PartialKeyPath<Root>) {
        self.fieldNames = [Root.fieldName(for: field)]
    }

    /// Initialize with multiple KeyPaths for composite bitmap
    ///
    /// - Parameter fields: KeyPaths to fields
    public init(fields: [PartialKeyPath<Root>]) {
        self.fieldNames = fields.map { Root.fieldName(for: $0) }
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(fieldNames: [String]) {
        self.fieldNames = fieldNames
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard !types.isEmpty else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 1,
                actual: 0
            )
        }
        for type in types {
            guard TypeValidation.isComparable(type) else {
                throw IndexTypeValidationError.unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "Bitmap index requires Comparable types"
                )
            }
        }
    }
}

// MARK: - TimeWindowLeaderboardIndexKind

/// Time-windowed leaderboard index for ranking with automatic window rotation
///
/// **Type-Safe Design**: The `Score` type parameter preserves the score type,
/// ensuring rankings work correctly with the original numeric type.
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct GameScore {
///     var playerId: String
///     var score: Int64
///
///     #Index<GameScore>(type: TimeWindowLeaderboardIndexKind(
///         scoreField: \.score,
///         window: .daily,
///         windowCount: 7  // Keep last 7 days
///     ))
///     // Infers: TimeWindowLeaderboardIndexKind<GameScore, Int64>
/// }
/// ```
///
/// **Key Structure**:
/// ```
/// // Current window scores
/// Key: [indexSubspace]["window"][windowId][score][primaryKey]
/// Value: ''
///
/// // Window metadata
/// Key: [indexSubspace]["meta"]["current"]
/// Value: windowId
///
/// // Historical aggregates
/// Key: [indexSubspace]["history"][windowId]
/// Value: Tuple(startTime, endTime, topScores...)
/// ```
///
/// **Supports**:
/// - Top-K queries within current window
/// - Historical window queries
/// - Automatic window rotation
/// - Cross-window aggregation
/// - Type preservation for scores
///
/// **Reference**: FDB Record Layer TIME_WINDOW_LEADERBOARD index type
public struct TimeWindowLeaderboardIndexKind<Root: Persistable, Score: Comparable & Numeric & Codable & Sendable>: IndexKind {
    public static var identifier: String { "time_window_leaderboard" }
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    /// Field name for the score to rank
    public let scoreFieldName: String

    /// Score type name for Codable reconstruction
    public let scoreTypeName: String

    /// Window type
    public let window: LeaderboardWindowType

    /// Number of windows to keep (history depth)
    public let windowCount: Int

    /// Optional grouping fields (e.g., by region, by game mode)
    public let groupByFieldNames: [String]

    /// All field names for IndexKind protocol
    public var fieldNames: [String] {
        groupByFieldNames + [scoreFieldName]
    }

    /// Default index name
    public var indexName: String {
        let scoreName = scoreFieldName.replacingOccurrences(of: ".", with: "_")
        if groupByFieldNames.isEmpty {
            return "\(Root.persistableType)_leaderboard_\(scoreName)"
        }
        let groupNames = groupByFieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        return "\(Root.persistableType)_leaderboard_\(groupNames.joined(separator: "_"))_\(scoreName)"
    }

    /// Initialize with KeyPaths - type is inferred from KeyPath
    ///
    /// - Parameters:
    ///   - scoreField: KeyPath to the score field (type inferred)
    ///   - groupBy: Optional grouping fields (default: empty)
    ///   - window: Window type (default: daily)
    ///   - windowCount: Number of windows to keep (default: 7)
    public init(
        scoreField: KeyPath<Root, Score>,
        groupBy: [PartialKeyPath<Root>] = [],
        window: LeaderboardWindowType = .daily,
        windowCount: Int = 7
    ) {
        self.scoreFieldName = Root.fieldName(for: scoreField)
        self.scoreTypeName = String(describing: Score.self)
        self.groupByFieldNames = groupBy.map { Root.fieldName(for: $0) }
        self.window = window
        self.windowCount = windowCount
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(
        scoreFieldName: String,
        scoreTypeName: String,
        groupByFieldNames: [String] = [],
        window: LeaderboardWindowType = .daily,
        windowCount: Int = 7
    ) {
        self.scoreFieldName = scoreFieldName
        self.scoreTypeName = scoreTypeName
        self.groupByFieldNames = groupByFieldNames
        self.window = window
        self.windowCount = windowCount
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard !types.isEmpty else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 1,
                actual: 0
            )
        }
        // Score field must be comparable
        guard let scoreType = types.last else { return }
        guard TypeValidation.isComparable(scoreType) else {
            throw IndexTypeValidationError.unsupportedType(
                index: identifier,
                type: scoreType,
                reason: "Leaderboard score field must be Comparable"
            )
        }
    }
}

/// Leaderboard window type
public enum LeaderboardWindowType: Sendable, Hashable, Codable {
    /// Hourly windows
    case hourly
    /// Daily windows (default)
    case daily
    /// Weekly windows
    case weekly
    /// Monthly windows
    case monthly
    /// Custom duration in seconds
    case custom(duration: TimeInterval)

    /// Duration in seconds
    public var durationSeconds: TimeInterval {
        switch self {
        case .hourly:
            return 3600
        case .daily:
            return 86400
        case .weekly:
            return 604800
        case .monthly:
            return 2592000  // 30 days
        case .custom(let duration):
            return duration
        }
    }
}

// MARK: - DistinctIndexKind

/// Aggregation index for estimating distinct (unique) values using HyperLogLog++
///
/// **Algorithm**: HyperLogLog++ (probabilistic cardinality estimation)
/// - Accuracy: ~0.81% standard error (precision=14)
/// - Memory: ~16KB per group
/// - Supports merge for distributed computation
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct PageView {
///     var pageId: String
///     var userId: String
///
///     // Count unique visitors per page
///     #Index<PageView>(type: DistinctIndexKind(groupBy: [\.pageId], value: \.userId))
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][groupKey1][groupKey2]... = HyperLogLog (serialized)`
///
/// **Important Limitations**:
/// - Add-only: Cannot remove values once added
/// - Approximate: Results are estimates, not exact counts
/// - After deletion, cardinality does NOT decrease
///
/// **Best for**:
/// - Counting unique visitors/users
/// - Cardinality estimation for high-cardinality fields
/// - Analytics where ~1% error is acceptable
///
/// **Reference**: Heule, Nunkesser, Hall. "HyperLogLog in Practice" (Google, 2013)
public struct DistinctIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "distinct" }
    public static var subspaceStructure: SubspaceStructure { .aggregation }

    /// Field names for grouping
    public let groupByFieldNames: [String]

    /// Field name for the value to count distinct
    public let valueFieldName: String

    /// HyperLogLog precision parameter (default: 14)
    /// - p=14: 16KB memory, ~0.81% error
    /// - p=12: 4KB memory, ~1.63% error
    public let precision: Int

    /// All field names (groupBy + value) for IndexKind protocol
    public var fieldNames: [String] {
        groupByFieldNames + [valueFieldName]
    }

    /// Default index name: "{TypeName}_distinct_{groupFields}_{valueField}"
    public var indexName: String {
        let groupNames = groupByFieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        let valueName = valueFieldName.replacingOccurrences(of: ".", with: "_")
        if groupNames.isEmpty {
            return "\(Root.persistableType)_distinct_\(valueName)"
        }
        return "\(Root.persistableType)_distinct_\(groupNames.joined(separator: "_"))_\(valueName)"
    }

    /// Initialize with KeyPaths
    ///
    /// - Parameters:
    ///   - groupBy: KeyPaths to grouping fields (empty for global distinct)
    ///   - value: KeyPath to the field to count distinct values
    ///   - precision: HyperLogLog precision parameter (default: 14)
    public init(groupBy: [PartialKeyPath<Root>] = [], value: PartialKeyPath<Root>, precision: Int = 14) {
        self.groupByFieldNames = groupBy.map { Root.fieldName(for: $0) }
        self.valueFieldName = Root.fieldName(for: value)
        self.precision = precision
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(groupByFieldNames: [String], valueFieldName: String, precision: Int = 14) {
        self.groupByFieldNames = groupByFieldNames
        self.valueFieldName = valueFieldName
        self.precision = precision
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.count >= 1 else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 1,
                actual: 0
            )
        }
        // Value field can be any Hashable type (will be hashed for HLL)
        // Grouping fields must be Comparable (for key construction)
        let groupingTypes = types.dropLast()
        for type in groupingTypes {
            guard TypeValidation.isComparable(type) else {
                throw IndexTypeValidationError.unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "Distinct index grouping fields must be Comparable"
                )
            }
        }
    }
}

// MARK: - PercentileIndexKind

/// Aggregation index for estimating percentiles using t-digest
///
/// **Algorithm**: t-digest (streaming quantile estimation)
/// - High accuracy at extreme percentiles (p99, p99.9)
/// - Memory: ~10KB per group (compression=100)
/// - Supports merge for distributed computation
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct ResponseTime {
///     var endpoint: String
///     var latencyMs: Double
///
///     // Track latency percentiles per endpoint
///     #Index<ResponseTime>(type: PercentileIndexKind(groupBy: [\.endpoint], value: \.latencyMs))
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][groupKey1][groupKey2]... = TDigest (serialized)`
///
/// **Important Limitations**:
/// - Add-only: Cannot remove values once added
/// - Approximate: Results are estimates
/// - After deletion, percentiles do NOT update
///
/// **Best for**:
/// - Latency monitoring (p50, p90, p99, p99.9)
/// - Response time analytics
/// - Any scenario needing streaming quantile estimation
///
/// **Reference**: Dunning, T. & Ertl, O. "Computing Extremely Accurate Quantiles Using t-Digests" (2019)
public struct PercentileIndexKind<Root: Persistable, Value: Numeric & Comparable & Codable & Sendable>: IndexKind {
    public static var identifier: String { "percentile" }
    public static var subspaceStructure: SubspaceStructure { .aggregation }

    /// Field names for grouping
    public let groupByFieldNames: [String]

    /// Field name for the value to track percentiles
    public let valueFieldName: String

    /// Value type name for Codable reconstruction
    public let valueTypeName: String

    /// t-digest compression parameter (default: 100)
    /// - Higher = more accuracy, more memory
    /// - 50: Lower memory, less accuracy
    /// - 100: Balanced (recommended)
    /// - 200: Higher accuracy, more memory
    public let compression: Double

    /// All field names (groupBy + value) for IndexKind protocol
    public var fieldNames: [String] {
        groupByFieldNames + [valueFieldName]
    }

    /// Default index name: "{TypeName}_percentile_{groupFields}_{valueField}"
    public var indexName: String {
        let groupNames = groupByFieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        let valueName = valueFieldName.replacingOccurrences(of: ".", with: "_")
        if groupNames.isEmpty {
            return "\(Root.persistableType)_percentile_\(valueName)"
        }
        return "\(Root.persistableType)_percentile_\(groupNames.joined(separator: "_"))_\(valueName)"
    }

    /// Initialize with KeyPaths
    ///
    /// - Parameters:
    ///   - groupBy: KeyPaths to grouping fields (empty for global percentile)
    ///   - value: KeyPath to the numeric field to track percentiles
    ///   - compression: t-digest compression parameter (default: 100)
    public init(groupBy: [PartialKeyPath<Root>] = [], value: KeyPath<Root, Value>, compression: Double = 100) {
        self.groupByFieldNames = groupBy.map { Root.fieldName(for: $0) }
        self.valueFieldName = Root.fieldName(for: value)
        self.valueTypeName = String(describing: Value.self)
        self.compression = compression
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(groupByFieldNames: [String], valueFieldName: String, valueTypeName: String, compression: Double = 100) {
        self.groupByFieldNames = groupByFieldNames
        self.valueFieldName = valueFieldName
        self.valueTypeName = valueTypeName
        self.compression = compression
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.count >= 1 else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 1,
                actual: 0
            )
        }
        // Grouping fields must be Comparable
        let groupingTypes = types.dropLast()
        for type in groupingTypes {
            guard TypeValidation.isComparable(type) else {
                throw IndexTypeValidationError.unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "Percentile index grouping fields must be Comparable"
                )
            }
        }
        // Value field must be Numeric
        guard let valueType = types.last else { return }
        guard TypeValidation.isNumeric(valueType) else {
            throw IndexTypeValidationError.unsupportedType(
                index: identifier,
                type: valueType,
                reason: "Percentile index value field must be Numeric"
            )
        }
    }
}
