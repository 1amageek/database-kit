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
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Order {
///     #Index(type: SumIndexKind<Order>(groupBy: [\.customerId], value: \.amount))
///     var customerId: String
///     var amount: Double
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][groupKey1][groupKey2]... = Double(sum)`
///
/// **Supports**:
/// - Get sum by group key
/// - Atomic add/subtract on insert/update/delete
/// - Multiple grouping fields
public struct SumIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "sum" }
    public static var subspaceStructure: SubspaceStructure { .aggregation }

    /// Field names for grouping
    public let groupByFieldNames: [String]

    /// Field name for the value to sum
    public let valueFieldName: String

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

    /// Initialize with KeyPaths
    ///
    /// - Parameters:
    ///   - groupBy: KeyPaths to grouping fields
    ///   - value: KeyPath to the numeric field to sum
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
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Product {
///     #Index(type: MinIndexKind<Product>(groupBy: [\.category], value: \.price))
///     var category: String
///     var price: Double
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][groupKey][value][primaryKey] = ''`
///
/// **Supports**:
/// - Get minimum value by group key
/// - Efficient min tracking via sorted storage
public struct MinIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "min" }
    public static var subspaceStructure: SubspaceStructure { .flat }

    /// Field names for grouping
    public let groupByFieldNames: [String]

    /// Field name for the value to track minimum
    public let valueFieldName: String

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

    /// Initialize with KeyPaths
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
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Product {
///     #Index(type: MaxIndexKind<Product>(groupBy: [\.category], value: \.price))
///     var category: String
///     var price: Double
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][groupKey][value][primaryKey] = ''`
///
/// **Supports**:
/// - Get maximum value by group key
/// - Efficient max tracking via reverse-sorted storage
public struct MaxIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "max" }
    public static var subspaceStructure: SubspaceStructure { .flat }

    /// Field names for grouping
    public let groupByFieldNames: [String]

    /// Field name for the value to track maximum
    public let valueFieldName: String

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

    /// Initialize with KeyPaths
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
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Review {
///     #Index(type: AverageIndexKind<Review>(groupBy: [\.productID], value: \.rating))
///     var productID: Int64
///     var rating: Int64  // Rating * 100 (e.g., 4.5 stars = 450)
/// }
/// ```
///
/// **Key Structure**:
/// - `[indexSubspace][groupKey]["sum"] = Int64(sum)`
/// - `[indexSubspace][groupKey]["count"] = Int64(count)`
///
/// **Supports**:
/// - Get average by group key (average = sum / count)
/// - Atomic increment/decrement on insert/update/delete
///
/// **Important**: Use Int64 for exact arithmetic
/// - ✅ Multiply by 100 or 1000 for decimal precision
/// - ❌ Do not use Double/Float (floating-point errors accumulate)
public struct AverageIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "average" }
    public static var subspaceStructure: SubspaceStructure { .aggregation }

    /// Field names for grouping
    public let groupByFieldNames: [String]

    /// Field name for the value to average
    public let valueFieldName: String

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

    /// Initialize with KeyPaths
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
