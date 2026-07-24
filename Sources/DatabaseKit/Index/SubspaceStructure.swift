import DatabaseTypes
// SubspaceStructure.swift
// Logical index state structure.

/// Index Subspace structure type
///
/// **Design principles**:
/// - database-kit declares the logical structure
/// - database-framework selects and executes the concrete layout
/// - storage-kit remains unaware of index meaning
///
/// **Example**:
/// ```swift
/// // Scalar index
/// let structure = SubspaceStructure.flat
///
/// // HNSW index
/// let structure = SubspaceStructure.hierarchical
///
/// // Count index
/// let structure = SubspaceStructure.aggregation
/// ```
public enum SubspaceStructure: String, Sendable, Hashable {
    /// Flat structure: [value][primaryKey] = ''
    ///
    /// **Key structure**: Simple 2-level
    /// **Examples**: Scalar, Rank, Version
    /// - `[indexSubspace][fieldValue][pk] = ''`
    ///
    /// **Characteristics**:
    /// - Simple and fast
    /// - Optimal for Range reads
    /// - No DirectoryLayer needed
    ///
    /// **Example**:
    /// ```swift
    /// // Email search index
    /// // Key: [index][alice@example.com][userID_123] = ''
    /// ```
    case flat

    /// Hierarchical structure: Multiple subpaths
    ///
    /// **Key structure**: Complex multi-level hierarchy
    /// **Examples**: Vector (HNSW), Spatial, Graph
    /// - `[indexSubspace][metadata/vectors/layers/...][...]`
    /// - May be dynamically created with DirectoryLayer at runtime
    ///
    /// **Characteristics**:
    /// - Has multiple subspaces
    /// - Can be shortened with DirectoryLayer prefix
    /// - Dynamic subpath creation (HNSW layers, etc.)
    ///
    /// **Example**:
    /// ```swift
    /// // HNSW index
    /// // Key: [index][metadata][...]
    /// //      [index][vectors][vectorID]
    /// //      [index][layers/0][nodeID]
    /// //      [index][layers/1][nodeID]
    /// ```
    case hierarchical

    /// Aggregation structure: [groupKey] → aggregatedValue
    ///
    /// **Key structure**: Grouping key → aggregated value
    /// **Examples**: Count, Sum, Min, Max
    /// - `[indexSubspace][groupKey] = Int64(aggregatedValue)`
    ///
    /// **Characteristics**:
    /// - Store value directly
    /// - Update with AtomicOp
    /// - No DirectoryLayer needed
    ///
    /// **Example**:
    /// ```swift
    /// // User count by city
    /// // Key: [index][Tokyo] = Int64(12345)
    /// //      [index][Osaka] = Int64(5678)
    /// ```
    case aggregation
}
