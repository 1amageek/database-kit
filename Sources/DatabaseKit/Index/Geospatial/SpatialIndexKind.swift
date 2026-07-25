// SpatialIndexKind.swift
// Geospatial index declaration metadata.

import DatabaseTypes

/// Spatial encoding type
public enum SpatialEncoding: String, Sendable, Hashable {
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
///     var id: String
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
    public typealias Model = Root

    /// Identifier: "spatial"
    public static var identifier: String { "spatial" }

    /// Subspace structure: flat
    public static var subspaceStructure: SubspaceStructure { .flat }

    public let indexFields: [IndexField<Root>]

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

    public init(
        location: IndexField<Root>,
        encoding: SpatialEncoding = .s2,
        level: Int = 15
    ) {
        self.indexFields = [location]
        self.encoding = encoding
        self.level = level
    }

    package init(
        canonicalFields: [IndexFieldMetadata],
        encoding: SpatialEncoding = .s2,
        level: Int = 15
    ) {
        self.indexFields = canonicalFields.map {
            IndexField<Root>(metadata: $0)
        }
        self.encoding = encoding
        self.level = level
    }

    public func validateConfiguration() throws(IndexValidationError) {
        let maximumLevel = encoding == .morton ? 20 : 30
        guard (0...maximumLevel).contains(level) else {
            throw .invalidConfiguration(
                index: Self.identifier,
                reason: "Level must be in 0...\(maximumLevel)"
            )
        }
    }

    /// Persisted field validation
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
        for field in fields {
            guard !field.isArray,
                  (field.type == .geographicPoint
                    || field.type == .geographicPosition) else {
                throw .unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Spatial indexes require a geographic point or position"
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
