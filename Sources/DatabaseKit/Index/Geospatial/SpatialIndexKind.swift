// SpatialIndexKind.swift
// Geospatial index declaration metadata.

import DatabaseTypes

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
///     #Index(
///         SpatialIndexKind<Restaurant>(
///             latitude: \.latitude,
///             longitude: \.longitude,
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
        let flattenedNames = fieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
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

    public func validateConfiguration() throws(IndexTypeValidationError) {
        let maximumLevel = encoding == .morton && fieldNames.count == 3
            ? 20
            : 30
        guard (0...maximumLevel).contains(level) else {
            throw .invalidConfiguration(
                index: Self.identifier,
                reason: "Level must be in 0...\(maximumLevel)"
            )
        }
        guard encoding != .s2 || fieldNames.count == 2 else {
            throw .invalidConfiguration(
                index: Self.identifier,
                reason: "S2 indexes require latitude and longitude fields"
            )
        }
    }

    /// Type validation
    public static func validateTypes(
        _ types: [Any.Type]
    ) throws(IndexTypeValidationError) {
        guard types.count >= 2 && types.count <= 3 else {
            throw .invalidTypeCount(
                index: identifier,
                expected: 2,
                actual: types.count
            )
        }
        for type in types {
            guard TypeValidation.isNumeric(
                TypeValidation.unwrapped(type)
            ) else {
                throw .unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "Spatial coordinates must be numeric"
                )
            }
        }
    }
}

// MARK: - Hashable Conformance

extension SpatialIndexKind {
    public var metadata: [String: FieldValue] {
        [
            "encoding": .string(encoding.rawValue),
            "level": .int64(Int64(level)),
        ]
    }

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
