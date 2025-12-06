// GraphIndexStrategy.swift
// Graph - Storage strategy for graph indexes (FDB-independent, iOS-compatible)
//
// Defines different indexing strategies for graph data with varying
// trade-offs between write cost and query performance.

import Foundation

/// Graph index storage strategy
///
/// Determines how many index orderings are maintained for graph edges.
/// More indexes = faster queries but higher write cost.
///
/// **Reference**: Weiss, C., Karras, P., & Bernstein, A. (2008).
/// "Hexastore: sextuple indexing for semantic web data management"
/// VLDB Endowment, 1(1), 1008-1019.
public enum GraphIndexStrategy: String, Sendable, Codable, CaseIterable {
    /// 2-index: outgoing and incoming edges only
    ///
    /// Optimized for storage efficiency and basic adjacency queries.
    /// Best for social graphs and simple traversal patterns.
    ///
    /// **Indexes**:
    /// - `[out]/[edge]/[from]/[to]` - outgoing edges
    /// - `[in]/[edge]/[to]/[from]` - incoming edges
    ///
    /// **Supported query patterns**:
    /// - `(from, ?, ?)` - all outgoing edges from a node
    /// - `(?, ?, to)` - all incoming edges to a node
    /// - `(from, edge, ?)` - outgoing edges with specific label
    /// - `(?, edge, to)` - incoming edges with specific label
    /// - `(from, edge, to)` - specific edge existence
    ///
    /// **Write cost**: 2 entries per edge
    case adjacency

    /// 3-index: SPO/POS/OSP orderings
    ///
    /// Standard RDF triple store pattern. Covers most SPARQL query patterns
    /// with at most one index scan per pattern.
    ///
    /// **Indexes**:
    /// - `[spo]/[from]/[edge]/[to]` - Subject-Predicate-Object
    /// - `[pos]/[edge]/[to]/[from]` - Predicate-Object-Subject
    /// - `[osp]/[to]/[from]/[edge]` - Object-Subject-Predicate
    ///
    /// **Supported query patterns** (all patterns, some require 2-step scan):
    /// - `(from, ?, ?)` - SPO index
    /// - `(?, edge, ?)` - POS index
    /// - `(?, ?, to)` - OSP index
    /// - `(from, edge, ?)` - SPO index
    /// - `(from, ?, to)` - OSP index (2-step: find from, filter)
    /// - `(?, edge, to)` - POS index
    ///
    /// **Write cost**: 3 entries per edge
    ///
    /// **Reference**: Neumann, T., & Weikum, G. (2010).
    /// "The RDF-3X engine for scalable management of RDF data"
    /// The VLDB Journal, 19(1), 91-113.
    case tripleStore

    /// 6-index: all permutations (hexastore)
    ///
    /// Maximum query performance with O(1) index selection for any pattern.
    /// Best for read-heavy workloads with diverse query patterns.
    ///
    /// **Indexes**:
    /// - `[spo]/[from]/[edge]/[to]` - Subject-Predicate-Object
    /// - `[sop]/[from]/[to]/[edge]` - Subject-Object-Predicate
    /// - `[pso]/[edge]/[from]/[to]` - Predicate-Subject-Object
    /// - `[pos]/[edge]/[to]/[from]` - Predicate-Object-Subject
    /// - `[osp]/[to]/[from]/[edge]` - Object-Subject-Predicate
    /// - `[ops]/[to]/[edge]/[from]` - Object-Predicate-Subject
    ///
    /// **Supported query patterns**: All patterns with optimal single-index scan
    ///
    /// **Write cost**: 6 entries per edge
    case hexastore

    /// Number of index entries created per edge
    public var indexCount: Int {
        switch self {
        case .adjacency: return 2
        case .tripleStore: return 3
        case .hexastore: return 6
        }
    }

    /// Human-readable description
    public var description: String {
        switch self {
        case .adjacency:
            return "Adjacency (2-index): optimized for basic graph traversal"
        case .tripleStore:
            return "Triple Store (3-index): RDF-compatible with SPO/POS/OSP"
        case .hexastore:
            return "Hexastore (6-index): all permutations for maximum query performance"
        }
    }
}

/// Index ordering for triple store queries
///
/// Used to specify which index to scan for a given query pattern.
public enum GraphIndexOrdering: String, Sendable, Codable, CaseIterable {
    // Adjacency orderings
    case out    // [edge]/[from]/[to]
    case `in`   // [edge]/[to]/[from]

    // Triple store orderings (SPO/POS/OSP)
    case spo    // [from]/[edge]/[to]
    case pos    // [edge]/[to]/[from]
    case osp    // [to]/[from]/[edge]

    // Hexastore additional orderings (SOP/PSO/OPS)
    case sop    // [from]/[to]/[edge]
    case pso    // [edge]/[from]/[to]
    case ops    // [to]/[edge]/[from]

    /// Element order for this index ordering
    ///
    /// Returns tuple indices for (from, edge, to) in the key order.
    /// For example, SPO returns [0, 1, 2] meaning from=0, edge=1, to=2.
    public var elementOrder: [Int] {
        switch self {
        case .out:  return [1, 0, 2]  // [edge]/[from]/[to]
        case .in:   return [1, 2, 0]  // [edge]/[to]/[from]
        case .spo:  return [0, 1, 2]  // [from]/[edge]/[to]
        case .sop:  return [0, 2, 1]  // [from]/[to]/[edge]
        case .pso:  return [1, 0, 2]  // [edge]/[from]/[to]
        case .pos:  return [1, 2, 0]  // [edge]/[to]/[from]
        case .osp:  return [2, 0, 1]  // [to]/[from]/[edge]
        case .ops:  return [2, 1, 0]  // [to]/[edge]/[from]
        }
    }
}
