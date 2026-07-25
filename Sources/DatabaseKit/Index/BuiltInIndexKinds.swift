import DatabaseTypes
// BuiltInIndexKinds.swift
// Built-in IndexKind definitions
//
// These definitions are storage-independent and can be used across all platforms.
// They are available from the Core declaration module.


// MARK: - ScalarIndexKind

/// Built-in VALUE index for sorting and range queries
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Product {
///     #Index(ScalarIndexKind<Product>(fields: [\.category, \.price]))
///     var category: String
///     var price: Int64
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
///
/// **Covering Index (Index-Only Scan)**:
/// Use `storedFields` on `#Index` macro to store additional fields:
/// ```swift
/// #Index(ScalarIndexKind<Product>(fields: [\.category]), storedFields: [\.name, \.price])
/// ```
public struct ScalarIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "scalar" }
    public static var subspaceStructure: SubspaceStructure { .flat }

    /// Field names for this index (stored as canonical field names)
    public let fieldNames: [String]

    /// Default index name: "{TypeName}_{field1}_{field2}_..."
    public var indexName: String {
        let flattenedNames = fieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
        return "\(Root.persistableType)_\(flattenedNames.joined(separator: "_"))"
    }

    /// Initialize with KeyPaths (converted to field names internally)
    ///
    /// - Parameter fields: KeyPaths to indexed fields
    public init(fields: [PartialKeyPath<Root>]) {
        self.fieldNames = fields.map { Root.fieldName(for: $0) }
    }

    /// Initialize with field name strings (from canonical metadata)
    public init(fieldNames: [String]) {
        self.fieldNames = fieldNames
    }

    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard !fields.isEmpty else {
            throw IndexValidationError.invalidFieldCount(
                index: identifier,
                expected: 1,
                actual: 0
            )
        }
        for field in fields {
            guard field.supportsOrderedIndex else {
                throw IndexValidationError.unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Scalar index requires Comparable fields"
                )
            }
        }
    }
}

// MARK: - CountIndexKind

/// Aggregation index for counting entities by grouping fields
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Order {
///     #Index(CountIndexKind<Order>(groupBy: [\.status, \.type]))
///     var status: String
///     var type: String
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][groupKey1][groupKey2]... = Int64(count)`
///
/// **Supports**:
/// - Get count by group key
/// - Checked increment/decrement in the caller's transaction
/// - Multiple grouping fields
public struct CountIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "count" }
    public static var subspaceStructure: SubspaceStructure { .aggregation }

    /// Field names for grouping (stored as canonical field names)
    public let fieldNames: [String]

    /// Default index name: "{TypeName}_count_{field1}_{field2}_..."
    public var indexName: String {
        let flattenedNames = fieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
        if flattenedNames.isEmpty {
            return "\(Root.persistableType)_count"
        }
        return "\(Root.persistableType)_count_\(flattenedNames.joined(separator: "_"))"
    }

    /// Initialize with KeyPaths (converted to field names internally)
    ///
    /// - Parameter groupBy: KeyPaths to grouping fields
    public init(groupBy: [PartialKeyPath<Root>]) {
        self.fieldNames = groupBy.map { Root.fieldName(for: $0) }
    }

    /// Initialize with field name strings (from canonical metadata)
    public init(fieldNames: [String]) {
        self.fieldNames = fieldNames
    }

    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        for field in fields {
            guard field.supportsOrderedIndex else {
                throw IndexValidationError.unsupportedField(
                    index: identifier,
                    field: field,
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
/// ensuring integers remain integers and floating-point fields use appropriate storage.
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Order {
///     var customerId: String
///     var amount: Int64  // Type preserved as Int64
///
///     #Index(SumIndexKind<Order, Int64>(groupBy: [\.customerId], value: \.amount))
/// }
/// ```
///
/// **Key Structure**:
/// - `[indexSubspace][groupKey1][groupKey2]...["sum"] = typed sum`
/// - `[indexSubspace][groupKey1][groupKey2]...["count"] = positive Int64`
///
/// **Storage**:
/// - Signed integer fields: Stored as exact Int64 bytes
/// - Unsigned integer fields: Stored as exact UInt64 bytes
/// - Floating-point fields: Stored as a finite compensated accumulator
///
/// **Supports**:
/// - Get sum by group key
/// - Checked read/replace mutations in the caller's transaction
/// - Multiple grouping fields
/// - Precision preservation for integer fields
public struct SumIndexKind<Root: Persistable, Value: IndexNumericValue>: IndexKind {
    public static var identifier: String { "sum" }
    public static var subspaceStructure: SubspaceStructure { .aggregation }

    /// Field names for grouping
    public let groupByFieldNames: [String]

    /// Field name for the value to sum
    public let valueFieldName: String

    /// Stable scalar type used by the runtime.
    public let valueType: IndexScalarType

    /// All field names (groupBy + value) for IndexKind protocol
    public var fieldNames: [String] {
        groupByFieldNames + [valueFieldName]
    }

    /// Default index name: "{TypeName}_sum_{groupField1}_{valueField}"
    public var indexName: String {
        let groupNames = groupByFieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
        let valueName = UTF8Text.replacingOccurrences(
            in: valueFieldName,
            of: ".",
            with: "_"
        )
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
        self.valueType = Value.indexScalarType
    }

    /// Initialize with field name strings (from canonical metadata)
    public init(
        groupByFieldNames: [String],
        valueFieldName: String,
        valueType: IndexScalarType
    ) {
        self.groupByFieldNames = groupByFieldNames
        self.valueFieldName = valueFieldName
        self.valueType = valueType
    }

    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard fields.count >= 1 else {
            throw IndexValidationError.invalidFieldCount(
                index: identifier,
                expected: 1,
                actual: fields.count
            )
        }
        let groupingFields = fields.dropLast()
        for field in groupingFields {
            guard field.supportsOrderedIndex else {
                throw IndexValidationError.unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Sum index grouping fields must be Comparable"
                )
            }
        }
        guard let valueField = fields.last else { return }
        guard valueField.isNumeric else {
            throw IndexValidationError.unsupportedField(
                index: identifier,
                field: valueField,
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
///     #Index(MinIndexKind<Product, Int64>(groupBy: [\.category], value: \.price))
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][groupKey][value][primaryKey] = ''`
///
/// **Supports**:
/// - Get minimum value by group key
/// - Efficient min tracking via sorted storage
/// - Type preservation for result
public struct MinIndexKind<Root: Persistable, Value: IndexComparableValue>: IndexKind {
    public static var identifier: String { "min" }
    public static var subspaceStructure: SubspaceStructure { .flat }

    /// Field names for grouping
    public let groupByFieldNames: [String]

    /// Field name for the value to track minimum
    public let valueFieldName: String

    /// Stable scalar type used by the runtime.
    public let valueType: IndexScalarType

    /// All field names (groupBy + value) for IndexKind protocol
    public var fieldNames: [String] {
        groupByFieldNames + [valueFieldName]
    }

    /// Default index name: "{TypeName}_min_{groupField1}_{valueField}"
    public var indexName: String {
        let groupNames = groupByFieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
        let valueName = UTF8Text.replacingOccurrences(
            in: valueFieldName,
            of: ".",
            with: "_"
        )
        if groupNames.isEmpty {
            return "\(Root.persistableType)_min_\(valueName)"
        }
        return "\(Root.persistableType)_min_\(groupNames.joined(separator: "_"))_\(valueName)"
    }

    /// Initialize with KeyPaths - type is inferred from KeyPath
    public init(groupBy: [PartialKeyPath<Root>], value: KeyPath<Root, Value>) {
        self.groupByFieldNames = groupBy.map { Root.fieldName(for: $0) }
        self.valueFieldName = Root.fieldName(for: value)
        self.valueType = Value.indexScalarType
    }

    /// Initialize with field name strings (from canonical metadata)
    public init(
        groupByFieldNames: [String],
        valueFieldName: String,
        valueType: IndexScalarType
    ) {
        self.groupByFieldNames = groupByFieldNames
        self.valueFieldName = valueFieldName
        self.valueType = valueType
    }

    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard fields.count >= 1 else {
            throw IndexValidationError.invalidFieldCount(
                index: identifier,
                expected: 1,
                actual: fields.count
            )
        }
        for field in fields {
            guard field.supportsOrderedIndex else {
                throw IndexValidationError.unsupportedField(
                    index: identifier,
                    field: field,
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
///     #Index(MaxIndexKind<Product, Int64>(groupBy: [\.category], value: \.price))
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][groupKey][value][primaryKey] = ''`
///
/// **Supports**:
/// - Get maximum value by group key
/// - Efficient max tracking via reverse-sorted storage
/// - Type preservation for result
public struct MaxIndexKind<Root: Persistable, Value: IndexComparableValue>: IndexKind {
    public static var identifier: String { "max" }
    public static var subspaceStructure: SubspaceStructure { .flat }

    /// Field names for grouping
    public let groupByFieldNames: [String]

    /// Field name for the value to track maximum
    public let valueFieldName: String

    /// Stable scalar type used by the runtime.
    public let valueType: IndexScalarType

    /// All field names (groupBy + value) for IndexKind protocol
    public var fieldNames: [String] {
        groupByFieldNames + [valueFieldName]
    }

    /// Default index name: "{TypeName}_max_{groupField1}_{valueField}"
    public var indexName: String {
        let groupNames = groupByFieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
        let valueName = UTF8Text.replacingOccurrences(
            in: valueFieldName,
            of: ".",
            with: "_"
        )
        if groupNames.isEmpty {
            return "\(Root.persistableType)_max_\(valueName)"
        }
        return "\(Root.persistableType)_max_\(groupNames.joined(separator: "_"))_\(valueName)"
    }

    /// Initialize with KeyPaths - type is inferred from KeyPath
    public init(groupBy: [PartialKeyPath<Root>], value: KeyPath<Root, Value>) {
        self.groupByFieldNames = groupBy.map { Root.fieldName(for: $0) }
        self.valueFieldName = Root.fieldName(for: value)
        self.valueType = Value.indexScalarType
    }

    /// Initialize with field name strings (from canonical metadata)
    public init(
        groupByFieldNames: [String],
        valueFieldName: String,
        valueType: IndexScalarType
    ) {
        self.groupByFieldNames = groupByFieldNames
        self.valueFieldName = valueFieldName
        self.valueType = valueType
    }

    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard fields.count >= 1 else {
            throw IndexValidationError.invalidFieldCount(
                index: identifier,
                expected: 1,
                actual: fields.count
            )
        }
        for field in fields {
            guard field.supportsOrderedIndex else {
                throw IndexValidationError.unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Max index requires all fields to be Comparable"
                )
            }
        }
    }
}

// MARK: - AverageIndexKind

/// Aggregation index for computing average values by grouping fields
///
/// **Type-Safe Design**: The `Value` type parameter determines the exact sum
/// storage domain. Runtime results preserve that domain through `FieldValue`.
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Review {
///     var productID: Int64
///     var rating: Int64
///
///     #Index(AverageIndexKind<Review, Int64>(groupBy: [\.productID], value: \.rating))
/// }
/// ```
///
/// **Key Structure**:
/// - `[indexSubspace][groupKey]["sum"] = typed sum`
/// - `[indexSubspace][groupKey]["count"] = positive Int64`
///
/// **Storage**:
/// - Signed integer fields: Sum stored as exact Int128 bytes
/// - Unsigned integer fields: Sum stored as exact UInt128 bytes
/// - Floating-point fields: Sum stored as a finite compensated accumulator
///
/// **Result**: Exact integer when integral; otherwise a losslessly representable
/// `Double`. A non-representable exact integer quotient fails explicitly.
///
/// **Supports**:
/// - Get average by group key
/// - Checked read/replace mutations in the caller's transaction
/// - Precision preservation for sum storage
public struct AverageIndexKind<Root: Persistable, Value: IndexNumericValue>: IndexKind {
    public static var identifier: String { "average" }
    public static var subspaceStructure: SubspaceStructure { .aggregation }

    /// Field names for grouping
    public let groupByFieldNames: [String]

    /// Field name for the value to average
    public let valueFieldName: String

    /// Stable scalar type used by the runtime.
    public let valueType: IndexScalarType

    /// All field names (groupBy + value) for IndexKind protocol
    public var fieldNames: [String] {
        groupByFieldNames + [valueFieldName]
    }

    /// Default index name: "{TypeName}_avg_{groupField1}_{valueField}"
    public var indexName: String {
        let groupNames = groupByFieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
        let valueName = UTF8Text.replacingOccurrences(
            in: valueFieldName,
            of: ".",
            with: "_"
        )
        if groupNames.isEmpty {
            return "\(Root.persistableType)_avg_\(valueName)"
        }
        return "\(Root.persistableType)_avg_\(groupNames.joined(separator: "_"))_\(valueName)"
    }

    /// Initialize with KeyPaths - type is inferred from KeyPath
    public init(groupBy: [PartialKeyPath<Root>], value: KeyPath<Root, Value>) {
        self.groupByFieldNames = groupBy.map { Root.fieldName(for: $0) }
        self.valueFieldName = Root.fieldName(for: value)
        self.valueType = Value.indexScalarType
    }

    /// Initialize with field name strings (from canonical metadata)
    public init(
        groupByFieldNames: [String],
        valueFieldName: String,
        valueType: IndexScalarType
    ) {
        self.groupByFieldNames = groupByFieldNames
        self.valueFieldName = valueFieldName
        self.valueType = valueType
    }

    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard fields.count >= 1 else {
            throw IndexValidationError.invalidFieldCount(
                index: identifier,
                expected: 1,
                actual: fields.count
            )
        }
        let groupingFields = fields.dropLast()
        for field in groupingFields {
            guard field.supportsOrderedIndex else {
                throw IndexValidationError.unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Average index grouping fields must be Comparable"
                )
            }
        }
        guard let valueField = fields.last else { return }
        guard valueField.isNumeric else {
            throw IndexValidationError.unsupportedField(
                index: identifier,
                field: valueField,
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
public enum VersionHistoryStrategy: Sendable, Hashable {
    /// Keep all versions (unlimited history)
    case keepAll

    /// Keep only the last N versions
    case keepLast(Int)

    /// Keep versions for a specific duration (in seconds)
    case keepForDuration(Double)
}

/// Index for tracking entity versions with history retention
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Document {
///     #Index(VersionIndexKind<Document>(field: \.id, strategy: .keepLast(10)))
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
        let flattenedNames = fieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
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

    /// Initialize with field name strings (from canonical metadata)
    public init(fieldNames: [String], strategy: VersionHistoryStrategy = .keepAll) {
        self.fieldNames = fieldNames
        self.strategy = strategy
    }

    public func validateConfiguration() throws(IndexValidationError) {
        switch strategy {
        case .keepAll:
            return
        case .keepLast(let count):
            guard count > 0 else {
                throw .invalidConfiguration(
                    index: Self.identifier,
                    reason: "Retained version count must be positive"
                )
            }
        case .keepForDuration(let duration):
            guard duration.isFinite, duration > 0 else {
                throw .invalidConfiguration(
                    index: Self.identifier,
                    reason: "Retention duration must be finite and positive"
                )
            }
        }
    }

    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard fields.count == 1 else {
            throw .invalidFieldCount(
                index: identifier,
                expected: 1,
                actual: fields.count
            )
        }
    }
}

// MARK: - CountUpdatesIndexKind

/// Index for tracking the number of times each entity has been updated
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Document {
///     #Index(CountUpdatesIndexKind<Document>(field: \.id))
///     var id: String
///     var content: String
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][primaryKey] = Int64(updateCount)`
///
/// **Supports**:
/// - Get update count for a specific entity
/// - Checked transactional increment on each update
/// - Query entities by update frequency
///
/// **Reference**: FDB Record Layer COUNT_UPDATES index type
public struct CountUpdatesIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "count_updates" }
    public static var subspaceStructure: SubspaceStructure { .flat }

    /// Field names (typically the primary key field)
    public let fieldNames: [String]

    /// Default index name: "{TypeName}_updates_{field}"
    public var indexName: String {
        let flattenedNames = fieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
        return "\(Root.persistableType)_updates_\(flattenedNames.joined(separator: "_"))"
    }

    /// Initialize with KeyPath
    ///
    /// - Parameter field: KeyPath to the field (typically the primary key)
    public init(field: PartialKeyPath<Root>) {
        self.fieldNames = [Root.fieldName(for: field)]
    }

    /// Initialize with field name strings (from canonical metadata)
    public init(fieldNames: [String]) {
        self.fieldNames = fieldNames
    }

    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard fields.count == 1 else {
            throw IndexValidationError.invalidFieldCount(
                index: identifier,
                expected: 1,
                actual: fields.count
            )
        }
    }
}

// MARK: - CountNotNullIndexKind

/// Aggregation index for counting entities where a field is not null
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct User {
///     #Index(CountNotNullIndexKind<User>(groupBy: [\.country], value: \.phoneNumber))
///     var country: String
///     var phoneNumber: String?
/// }
/// ```
///
/// **Key Structure**: `[indexSubspace][groupKey1][groupKey2]... = Int64(nonNullCount)`
///
/// **Supports**:
/// - Count non-null values by group key
/// - Checked transactional increment/decrement on insert/update/delete
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
        let groupNames = groupByFieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
        let valueName = UTF8Text.replacingOccurrences(
            in: valueFieldName,
            of: ".",
            with: "_"
        )
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

    /// Initialize with field name strings (from canonical metadata)
    public init(groupByFieldNames: [String], valueFieldName: String) {
        self.groupByFieldNames = groupByFieldNames
        self.valueFieldName = valueFieldName
    }

    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard fields.count >= 1 else {
            throw IndexValidationError.invalidFieldCount(
                index: identifier,
                expected: 1,
                actual: 0
            )
        }
        let groupingFields = fields.dropLast()
        for field in groupingFields {
            guard field.supportsOrderedIndex else {
                throw IndexValidationError.unsupportedField(
                    index: identifier,
                    field: field,
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
///     #Index(BitmapIndexKind<User>(field: \.status))
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
        let flattenedNames = fieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
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

    /// Initialize with field name strings (from canonical metadata)
    public init(fieldNames: [String]) {
        self.fieldNames = fieldNames
    }

    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard !fields.isEmpty else {
            throw IndexValidationError.invalidFieldCount(
                index: identifier,
                expected: 1,
                actual: 0
            )
        }
        for field in fields {
            guard field.supportsOrderedIndex else {
                throw IndexValidationError.unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Bitmap index requires Comparable fields"
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
///     #Index(TimeWindowLeaderboardIndexKind<GameScore>(
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
public struct TimeWindowLeaderboardIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "time_window_leaderboard" }
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    /// Field name for the score to rank
    public let scoreFieldName: String

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
        let scoreName = UTF8Text.replacingOccurrences(
            in: scoreFieldName,
            of: ".",
            with: "_"
        )
        if groupByFieldNames.isEmpty {
            return "\(Root.persistableType)_leaderboard_\(scoreName)"
        }
        let groupNames = groupByFieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
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
        scoreField: KeyPath<Root, Int64>,
        groupBy: [PartialKeyPath<Root>] = [],
        window: LeaderboardWindowType = .daily,
        windowCount: Int = 7
    ) {
        self.scoreFieldName = Root.fieldName(for: scoreField)
        self.groupByFieldNames = groupBy.map { Root.fieldName(for: $0) }
        self.window = window
        self.windowCount = windowCount
    }

    /// Initialize with field name strings (from canonical metadata)
    public init(
        scoreFieldName: String,
        groupByFieldNames: [String] = [],
        window: LeaderboardWindowType = .daily,
        windowCount: Int = 7
    ) {
        self.scoreFieldName = scoreFieldName
        self.groupByFieldNames = groupByFieldNames
        self.window = window
        self.windowCount = windowCount
    }

    public func validateConfiguration() throws(IndexValidationError) {
        guard windowCount > 0 else {
            throw .invalidConfiguration(
                index: Self.identifier,
                reason: "Window count must be positive"
            )
        }
        guard window.durationSeconds.isFinite,
              window.durationSeconds > 0 else {
            throw .invalidConfiguration(
                index: Self.identifier,
                reason: "Window duration must be finite and positive"
            )
        }
    }

    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard !fields.isEmpty else {
            throw IndexValidationError.invalidFieldCount(
                index: identifier,
                expected: 1,
                actual: 0
            )
        }
        for field in fields.dropLast() {
            guard field.supportsOrderedIndex else {
                throw .unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Leaderboard grouping fields must be Comparable"
                )
            }
        }
        guard let scoreField = fields.last else { return }
        guard scoreField.type == .int64 && !scoreField.isArray else {
            throw IndexValidationError.unsupportedField(
                index: identifier,
                field: scoreField,
                reason: "Leaderboard score field must be Int64"
            )
        }
    }
}

/// Leaderboard window type
public enum LeaderboardWindowType: Sendable, Hashable {
    /// Hourly windows
    case hourly
    /// Daily windows (default)
    case daily
    /// Weekly windows
    case weekly
    /// Monthly windows
    case monthly
    /// Custom duration in seconds
    case custom(duration: Double)

    /// Duration in seconds
    public var durationSeconds: Double {
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
///     #Index(DistinctIndexKind<PageView>(groupBy: [\.pageId], value: \.userId))
/// }
/// ```
///
/// **Physical Structure**:
/// - Exact canonical-value membership with positive reference counts
/// - A bounded binary HyperLogLog summary per group
/// - Final-reference deletion rebuilds the summary transactionally
///
/// **Important Limitations**:
/// - Results are estimates, not exact counts
/// - Delete/update work is bounded by the number of distinct members in a group
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
    /// - Supported persisted range: 4...17
    public let precision: Int

    /// All field names (groupBy + value) for IndexKind protocol
    public var fieldNames: [String] {
        groupByFieldNames + [valueFieldName]
    }

    /// Default index name: "{TypeName}_distinct_{groupFields}_{valueField}"
    public var indexName: String {
        let groupNames = groupByFieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
        let valueName = UTF8Text.replacingOccurrences(
            in: valueFieldName,
            of: ".",
            with: "_"
        )
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

    /// Initialize with field name strings (from canonical metadata)
    public init(groupByFieldNames: [String], valueFieldName: String, precision: Int = 14) {
        self.groupByFieldNames = groupByFieldNames
        self.valueFieldName = valueFieldName
        self.precision = precision
    }

    public func validateConfiguration() throws(IndexValidationError) {
        guard (4...17).contains(precision) else {
            throw .invalidConfiguration(
                index: Self.identifier,
                reason: "Precision must be in 4...17"
            )
        }
    }

    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard fields.count >= 1 else {
            throw IndexValidationError.invalidFieldCount(
                index: identifier,
                expected: 1,
                actual: 0
            )
        }
        let groupingFields = fields.dropLast()
        for field in groupingFields {
            guard field.supportsOrderedIndex else {
                throw IndexValidationError.unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Distinct index grouping fields must be Comparable"
                )
            }
        }
        guard let valueField = fields.last else {
            return
        }
        guard valueField.supportsEqualityIndex else {
            throw .unsupportedField(
                index: identifier,
                field: valueField,
                reason: "Distinct index values must be Hashable"
            )
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
///     #Index(PercentileIndexKind<ResponseTime, Double>(groupBy: [\.endpoint], value: \.latencyMs))
/// }
/// ```
///
/// **Physical Structure**:
/// - Exact canonical numeric membership with positive reference counts
/// - A strict bounded t-digest binary summary per group
/// - Deletes and updates rebuild affected summaries transactionally
///
/// **Important Limitations**:
/// - Results are estimates
/// - Delete/update work is bounded by the number of distinct values in a group
///
/// **Best for**:
/// - Latency monitoring (p50, p90, p99, p99.9)
/// - Response time analytics
/// - Any scenario needing streaming quantile estimation
///
/// **Reference**: Dunning, T. & Ertl, O. "Computing Extremely Accurate Quantiles Using t-Digests" (2019)
public struct PercentileIndexKind<Root: Persistable, Value: IndexNumericValue>: IndexKind {
    public static var identifier: String { "percentile" }
    public static var subspaceStructure: SubspaceStructure { .aggregation }

    /// Field names for grouping
    public let groupByFieldNames: [String]

    /// Field name for the value to track percentiles
    public let valueFieldName: String

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
        let groupNames = groupByFieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
        let valueName = UTF8Text.replacingOccurrences(
            in: valueFieldName,
            of: ".",
            with: "_"
        )
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
        self.compression = compression
    }

    /// Initialize with field name strings (from canonical metadata)
    public init(
        groupByFieldNames: [String],
        valueFieldName: String,
        compression: Double = 100
    ) {
        self.groupByFieldNames = groupByFieldNames
        self.valueFieldName = valueFieldName
        self.compression = compression
    }

    public func validateConfiguration() throws(IndexValidationError) {
        guard compression.isFinite,
              (1.0...1_000.0).contains(compression) else {
            throw .invalidConfiguration(
                index: Self.identifier,
                reason: "Compression must be finite and in 1...1000"
            )
        }
    }

    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard fields.count >= 1 else {
            throw IndexValidationError.invalidFieldCount(
                index: identifier,
                expected: 1,
                actual: 0
            )
        }
        // Grouping fields must be Comparable
        let groupingFields = fields.dropLast()
        for field in groupingFields {
            guard field.supportsOrderedIndex else {
                throw IndexValidationError.unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Percentile index grouping fields must be Comparable"
                )
            }
        }
        // Value field must be Numeric
        guard let valueField = fields.last else { return }
        guard valueField.isNumeric else {
            throw IndexValidationError.unsupportedField(
                index: identifier,
                field: valueField,
                reason: "Percentile index value field must be Numeric"
            )
        }
    }
}

// MARK: - Canonical Index Metadata

extension SumIndexKind {
    public var metadata: [String: FieldValue] {
        ["valueType": .string(valueType.rawValue)]
    }
}

extension MinIndexKind {
    public var metadata: [String: FieldValue] {
        ["valueType": .string(valueType.rawValue)]
    }
}

extension MaxIndexKind {
    public var metadata: [String: FieldValue] {
        ["valueType": .string(valueType.rawValue)]
    }
}

extension AverageIndexKind {
    public var metadata: [String: FieldValue] {
        ["valueType": .string(valueType.rawValue)]
    }
}

extension VersionIndexKind {
    public var metadata: [String: FieldValue] {
        switch strategy {
        case .keepAll:
            return ["strategy": .string("keepAll")]
        case .keepLast(let count):
            return [
                "strategy": .string("keepLast"),
                "strategyCount": .int64(Int64(count)),
            ]
        case .keepForDuration(let duration):
            return [
                "strategy": .string("keepForDuration"),
                "strategyDurationSeconds": .float64(duration),
            ]
        }
    }
}

extension TimeWindowLeaderboardIndexKind {
    public var metadata: [String: FieldValue] {
        var values: [String: FieldValue] = [
            "windowCount": .int64(Int64(windowCount)),
        ]
        switch window {
        case .hourly:
            values["window"] = .string("hourly")
        case .daily:
            values["window"] = .string("daily")
        case .weekly:
            values["window"] = .string("weekly")
        case .monthly:
            values["window"] = .string("monthly")
        case .custom(let duration):
            values["window"] = .string("custom")
            values["windowDurationSeconds"] = .float64(duration)
        }
        return values
    }
}

extension DistinctIndexKind {
    public var metadata: [String: FieldValue] {
        ["precision": .int64(Int64(precision))]
    }
}

extension PercentileIndexKind {
    public var metadata: [String: FieldValue] {
        ["compression": .float64(compression)]
    }
}
