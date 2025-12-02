// SpatialIndexKind.swift
// SpatialIndexModel - Spatial index metadata (FDB-independent, iOS-compatible)
//
// Defines metadata for geospatial indexes. This file is FDB-independent
// and can be used on all platforms including iOS clients.

import Foundation
import Core

/// Spatial encoding type
public enum SpatialEncoding: String, Sendable, Codable, Hashable {
    /// S2 Geometry encoding (Hilbert curve on sphere)
    /// Best for: Geographic coordinates (latitude/longitude)
    case s2

    /// Morton Code encoding (Z-order curve)
    /// Best for: Cartesian coordinates (x, y, z)
    case morton
}

/// Spatial index kind for geospatial queries
///
/// **Purpose**: Spatial indexing for location-based queries
/// - Radius queries (find within N meters)
/// - Bounding box queries (find in rectangle)
/// - Multiple encoding schemes (S2 Geometry, Morton Code)
///
/// **Index Structure**:
/// ```
/// Key: [indexSubspace][spatialCode][primaryKey]
/// Value: '' (empty)
/// ```
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Restaurant {
///     var id: String = ULID().ulidString
///
///     #Index<Restaurant>(
///         [\.latitude, \.longitude],
///         type: SpatialIndexKind(
///             encoding: .s2,
///             level: 15
///         )
///     )
///
///     var latitude: Double
///     var longitude: Double
/// }
/// ```
public struct SpatialIndexKind<Root: Persistable>: IndexKind {
    /// Identifier: "spatial"
    public static var identifier: String { "spatial" }

    /// Subspace structure: flat
    public static var subspaceStructure: SubspaceStructure { .flat }

    /// Field names for this index (lat/lon or x/y/z)
    public let fieldNames: [String]

    /// Spatial encoding scheme
    public let encoding: SpatialEncoding

    /// Precision level
    /// - S2: 0-30 (15 is typical for ~1m precision)
    /// - Morton: 0-30 for 2D, 0-20 for 3D
    public let level: Int

    /// Default index name: "{TypeName}_spatial_{fields}"
    public var indexName: String {
        let flattenedNames = fieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        return "\(Root.persistableType)_spatial_\(flattenedNames.joined(separator: "_"))"
    }

    /// Initialize with KeyPaths for 2D coordinates (lat/lon)
    ///
    /// - Parameters:
    ///   - latitude: KeyPath to latitude field
    ///   - longitude: KeyPath to longitude field
    ///   - encoding: Spatial encoding scheme (default: .s2)
    ///   - level: Precision level (default: 15)
    public init(
        latitude: PartialKeyPath<Root>,
        longitude: PartialKeyPath<Root>,
        encoding: SpatialEncoding = .s2,
        level: Int = 15
    ) {
        self.fieldNames = [Root.fieldName(for: latitude), Root.fieldName(for: longitude)]
        self.encoding = encoding
        self.level = level
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(fieldNames: [String], encoding: SpatialEncoding = .s2, level: Int = 15) {
        self.fieldNames = fieldNames
        self.encoding = encoding
        self.level = level
    }

    /// Type validation
    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.count >= 2 && types.count <= 3 else {
            throw SpatialIndexError.invalidConfiguration("Spatial index requires 2-3 fields (lat/lon or x/y/z)")
        }
    }
}

// MARK: - Hashable Conformance

extension SpatialIndexKind {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(Self.identifier)
        hasher.combine(fieldNames)
        hasher.combine(encoding)
        hasher.combine(level)
    }

    public static func == (lhs: SpatialIndexKind, rhs: SpatialIndexKind) -> Bool {
        return lhs.fieldNames == rhs.fieldNames && lhs.encoding == rhs.encoding && lhs.level == rhs.level
    }
}

// MARK: - Spatial Index Errors

/// Errors specific to spatial index operations
public enum SpatialIndexError: Error, CustomStringConvertible, Sendable {
    case invalidConfiguration(String)
    case invalidCoordinates(String)

    public var description: String {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid spatial index configuration: \(message)"
        case .invalidCoordinates(let message):
            return "Invalid coordinates: \(message)"
        }
    }
}
