# DatabaseKit

A Swift package providing platform-independent data model definitions and index type specifications. DatabaseKit works on all platforms including iOS, macOS, tvOS, watchOS, visionOS, Linux, and Windows.

## Overview

DatabaseKit provides the foundational types for defining persistable data models and index specifications without any database dependencies. This separation enables:

- **Client-side model sharing**: Use the same model definitions on iOS clients and server backends
- **Platform independence**: No FoundationDB or other database dependencies
- **Extensible index system**: Define custom index types through protocol conformance

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/database-kit.git", from: "1.0.0")
]
```

## Modules

| Module | Description |
|--------|-------------|
| `Core` | Persistable protocol, @Persistable macro, Schema, Serialization, FieldSchema, PersistableEnum |
| `Relationship` | RelationshipIndexKind for cross-type queries, @Relationship macro |
| `Vector` | VectorIndexKind for similarity search |
| `FullText` | FullTextIndexKind for text search |
| `Spatial` | SpatialIndexKind for geospatial queries |
| `Rank` | RankIndexKind for leaderboards |
| `Permuted` | PermutedIndexKind for alternative field orderings |
| `Graph` | AdjacencyIndexKind for graph relationships |
| `Triple` | TripleIndexKind for RDF/knowledge graph triples |
| `DatabaseKit` | All-in-one re-export (individual imports recommended) |

## Quick Start

```swift
import Core

@Persistable
struct User {
    #Directory<User>("app", "users")
    #Index<User>(ScalarIndexKind(fields: [\.email]), unique: true)
    #Index<User>(ScalarIndexKind(fields: [\.createdAt]))

    var email: String
    var name: String
    var createdAt: Date
}
```

## Directory Macro

The `#Directory` macro defines the storage path for persistable types. It supports both static paths and dynamic multi-tenant partitioning.

### Basic Usage

```swift
#Directory<User>("app", "users")
```

### Multi-tenant Partitioning

Use `Field(\.property)` to create dynamic path segments based on record fields:

```swift
@Persistable
struct Order {
    #Directory<Order>("tenants", Field(\.accountID), "orders", layer: .partition)

    var orderID: Int64
    var accountID: String  // Partition key
}
```

### Multi-level Partitioning

```swift
@Persistable
struct Message {
    #Directory<Message>(
        "tenants", Field(\.accountID),
        "channels", Field(\.channelID),
        "messages",
        layer: .partition
    )

    var messageID: String = ULID().ulidString
    var accountID: String  // First partition key
    var channelID: String  // Second partition key
    var content: String
}
```

### Directory Layer Types

| Layer | Description |
|-------|-------------|
| `.default` | Default directory |
| `.partition` | Multi-tenant partition (requires at least one Field in path) |

## Extensible Architecture

### Design Philosophy

DatabaseKit is built on a **protocol-based extensible architecture** that allows third parties to add custom index types without modifying the core framework. This is achieved through:

1. **IndexKind Protocol**: Defines the contract for index type metadata
2. **Type-safe validation**: Each index kind validates field types at definition time
3. **Codable support**: Index definitions can be serialized and shared across platforms

### IndexKind Protocol

The `IndexKind` protocol is the foundation for all index types:

```swift
public protocol IndexKind: Sendable, Codable, Hashable {
    /// Unique identifier (e.g., "scalar", "vector", "com.mycompany.custom")
    static var identifier: String { get }

    /// Subspace structure type
    static var subspaceStructure: SubspaceStructure { get }

    /// Auto-generated index name (can be overridden in #Index macro)
    var indexName: String { get }

    /// Field names used by this index
    var fieldNames: [String] { get }

    /// Validate whether this index kind supports specified types
    static func validateTypes(_ types: [Any.Type]) throws
}
```

### Built-in Index Kinds

```swift
// Standard indexes (in Core module) - Generic over Root: Persistable
ScalarIndexKind<T>(fields: [\.field1, \.field2])     // VALUE index for sorting and range queries
CountIndexKind<T>(groupBy: [\.field])                // Count aggregation
SumIndexKind<T, V>(groupBy: [\.group], value: \.num) // Sum aggregation (V: Numeric)
MinIndexKind<T, V>(groupBy: [\.group], value: \.num) // Minimum value tracking (V: Comparable)
MaxIndexKind<T, V>(groupBy: [\.group], value: \.num) // Maximum value tracking (V: Comparable)
AverageIndexKind<T, V>(groupBy: [\.g], value: \.num) // Average calculation (V: Numeric)
VersionIndexKind<T>(field: \.id, strategy: .keepAll) // Version history tracking
CountUpdatesIndexKind<T>(field: \.id)                // Update count tracking
CountNotNullIndexKind<T>(groupBy: [\.g], value: \.f) // Non-null value counting
BitmapIndexKind<T>(field: \.status)                  // Bitmap index (low-cardinality)
TimeWindowLeaderboardIndexKind<T, S>(scoreField: \.score, window: .daily) // Time-windowed leaderboard

// Extended indexes (separate modules)
VectorIndexKind<T>(...)           // Vector similarity search (Vector module)
FullTextIndexKind<T>(...)         // Full-text search (FullText module)
SpatialIndexKind<T>(...)          // Geospatial queries (Spatial module)
RankIndexKind<T, S>(field: \.score) // Leaderboard rankings (Rank module)
TripleIndexKind<T>(...)           // RDF triple indexes (Triple module)
AdjacencyIndexKind<T>(...)        // Graph adjacency (Graph module)
PermutedIndexKind<T>(...)         // Field permutation (Permuted module)
RelationshipIndexKind<T, R>(...)  // Cross-type queries (Relationship module)
```

### TripleIndexKind (RDF/Knowledge Graph)

The `TripleIndexKind` enables efficient storage and querying of RDF-style triples (Subject-Predicate-Object) using three index orderings:

```swift
import Triple

@Persistable
struct Statement {
    var subject: String    // e.g., "Engineer"
    var predicate: String  // e.g., "rdfs:subClassOf"
    var object: String     // e.g., "Employee"

    #Index<Statement>(TripleIndexKind(
        subject: \.subject,
        predicate: \.predicate,
        object: \.object
    ))
}
```

**Index Structure:**
| Index | Key Order | Query Pattern |
|-------|-----------|---------------|
| SPO | Subject → Predicate → Object | S??, SP?, SPO |
| POS | Predicate → Object → Subject | ?P?, ?PO |
| OSP | Object → Subject → Predicate | ??O |

**Combining with VectorIndex for semantic search:**

```swift
import Vector

@Persistable
struct SemanticStatement {
    var subject: String
    var predicate: String
    var predicateEmbedding: [Float]  // Vector representation
    var object: String

    // Structural queries (SPO/POS/OSP)
    #Index<SemanticStatement>(TripleIndexKind(
        subject: \.subject,
        predicate: \.predicate,
        object: \.object
    ))

    // Semantic similarity search on predicates
    #Index<SemanticStatement>(VectorIndexKind(
        embedding: \.predicateEmbedding,
        dimensions: 384,
        metric: .cosine
    ))
}
```

## Creating Custom Index Kinds

Third parties can create custom index types by conforming to `IndexKind`:

```swift
import Core

/// Custom time-series index for efficient time-range queries
public struct TimeSeriesIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "com.mycompany.timeseries" }
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    public let fieldNames: [String]
    public let resolution: TimeResolution
    public let retention: TimeInterval?

    public enum TimeResolution: String, Codable, Sendable {
        case second, minute, hour, day
    }

    public var indexName: String {
        "\(Root.persistableType)_timeseries_\(fieldNames.joined(separator: "_"))"
    }

    public init(
        fields: [PartialKeyPath<Root>],
        resolution: TimeResolution = .minute,
        retention: TimeInterval? = nil
    ) {
        self.fieldNames = fields.map { Root.fieldName(for: $0) }
        self.resolution = resolution
        self.retention = retention
    }

    public init(fieldNames: [String], resolution: TimeResolution = .minute, retention: TimeInterval? = nil) {
        self.fieldNames = fieldNames
        self.resolution = resolution
        self.retention = retention
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.count >= 1 else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier, expected: 1, actual: types.count
            )
        }
        // First field must be Date
        guard types[0] == Date.self else {
            throw IndexTypeValidationError.unsupportedType(
                index: identifier,
                type: types[0],
                reason: "First field must be Date"
            )
        }
    }
}

// Usage
@Persistable
struct SensorReading {
    #Index<SensorReading>(TimeSeriesIndexKind(
        fields: [\.timestamp, \.sensorId],
        resolution: .second
    ))

    var timestamp: Date
    var sensorId: String
    var value: Double
}
```

## SubspaceStructure

Index kinds declare their storage structure:

```swift
public enum SubspaceStructure: String, Sendable, Codable {
    /// Flat key-value: [value][pk] = ''
    case flat

    /// Hierarchical structure (HNSW graphs, trees, etc.)
    case hierarchical

    /// Aggregated values (COUNT, SUM stored directly)
    case aggregation
}
```

## Model Definition

### @Persistable Macro

The `@Persistable` macro generates all required protocol conformances:

```swift
@Persistable
struct Product {
    // ID is auto-generated as ULID if not defined
    // var id: String = ULID().ulidString

    #Index<Product>(ScalarIndexKind(fields: [\.category, \.price]))
    #Index<Product>(ScalarIndexKind(fields: [\.name]), unique: true)

    var name: String
    var category: String
    var price: Double

    @Transient
    var cachedDescription: String?  // Excluded from persistence
}
```

### Generated Code

The macro generates:
- `var id: String = ULID().ulidString` (if not user-defined)
- `static var persistableType: String`
- `static var allFields: [String]`
- `static var fieldSchemas: [FieldSchema]` (field names, types, field numbers, optionality)
- `static func enumMetadata(for fieldName: String) -> EnumMetadata?` (runtime enum case extraction)
- `static var indexDescriptors: [IndexDescriptor]`
- `static var relationshipDescriptors: [RelationshipDescriptor]`
- `Codable`, `Sendable` conformances
- Dynamic member lookup support

## Relationship Module

The Relationship module enables efficient cross-type queries without JOINs using the `@Relationship` macro and `RelationshipIndexKind`.

### @Relationship Macro

```swift
import Core
import Relationship

@Persistable
struct Customer {
    var name: String
    var email: String
}

@Persistable
struct Order {
    var total: Double
    var status: String

    // Define relationship with index on related type's fields
    @Relationship(Customer.self, indexFields: [\.name])
    var customerID: String?
}
```

### How It Works

The `@Relationship` macro generates:
1. A `RelationshipDescriptor` for metadata
2. A `RelationshipIndexKind` for cross-type queries

This enables queries like "Find Orders where Customer.name = 'Alice'" without JOIN operations.

### RelationshipIndexKind

```swift
// Manual usage (the @Relationship macro generates this automatically)
#Index<Order>(RelationshipIndexKind(
    foreignKey: \.customerID,
    relatedFields: [\.name]
))
```

### Delete Rules

```swift
@Relationship(Customer.self, deleteRule: .cascade)
var customerID: String?
```

| Rule | Behavior |
|------|----------|
| `.nullify` | Set FK to null when related record deleted (default) |
| `.cascade` | Delete this record when related record deleted |
| `.deny` | Prevent deletion if related records exist |
| `.noAction` | No automatic action |

## PersistableEnum

Enum types used as fields in `@Persistable` models should conform to `PersistableEnum`. This enables automatic enum metadata generation for the schema catalog, allowing CLI tools to display valid cases and validate values.

```swift
import Core

enum Status: String, PersistableEnum {
    case active
    case inactive
    case pending
}

enum Priority: Int, PersistableEnum {
    case low = 0
    case medium = 1
    case high = 2
}

@Persistable
struct Task {
    #Directory<Task>("app", "tasks")

    var title: String
    var status: Status = .pending
    var priority: Priority = .medium
}
```

`PersistableEnum` combines `Sendable`, `Codable`, `CaseIterable`, and `RawRepresentable`. The `@Persistable` macro automatically generates `enumMetadata(for:)` that extracts case information at runtime for fields whose types conform to `PersistableEnum`.

### FieldSchemaType Resolution

The `@Persistable` macro classifies field types at compile time. For types it cannot recognize as primitives (String, Int, Double, Bool, Date, UUID, Data), it generates `FieldSchemaType.resolve(TypeName.self)` which checks `RawRepresentable` conformance at runtime:

- `RawRepresentable` types → `.enum`
- All other types → `.nested`

## Schema Definition

```swift
let schema = Schema(
    entities: [
        Schema.Entity(from: User.self),
        Schema.Entity(from: Product.self),
    ],
    version: Schema.Version(1, 0, 0)
)
```

## Serialization

DatabaseKit includes efficient Protobuf-compatible serialization:

```swift
let user = User(email: "alice@example.com", name: "Alice")

// Encode
let data = try ProtobufEncoder().encode(user)

// Decode
let decoded = try ProtobufDecoder().decode(User.self, from: data)
```

## Platform Support

| Platform | Minimum Version |
|----------|-----------------|
| iOS | 18.0+ |
| macOS | 15.0+ |
| tvOS | 18.0+ |
| watchOS | 11.0+ |
| visionOS | 2.0+ |
| Linux | Swift 6.2+ |
| Windows | Swift 6.2+ |

## Related Packages

### [DatabaseFramework](https://github.com/1amageek/database-framework)

Server-side database operations powered by FoundationDB. DatabaseFramework implements the index maintenance logic for index types defined in DatabaseKit.

**Key Features:**
- **FDBContainer**: Application resource manager
- **FDBContext**: Change tracking and batch operations
- **Index Maintainers**: Concrete implementations for all index types
- **Schema Versioning**: Online index building and migrations

**Architecture:**
- **Index Type Definition** (IndexKind in DatabaseKit): Platform-independent metadata
- **Index Maintenance** (IndexKindMaintainable in DatabaseFramework): Server-side implementation

**Server Modules:**
| Module | Description |
|--------|-------------|
| `DatabaseEngine` | Container, context, and index maintainer protocol |
| `ScalarIndex` | VALUE index implementation |
| `VectorIndex` | HNSW and flat vector search |
| `FullTextIndex` | Inverted index for text search |
| `SpatialIndex` | S2/Geohash spatial indexing |
| `RankIndex` | Skip-list based rankings |
| `GraphIndex` | Adjacency list traversal |
| `TripleIndex` | RDF triple store with SPO/POS/OSP indexes |
| `AggregationIndex` | COUNT, SUM, MIN, MAX, AVG operations |
| `VersionIndex` | Version history with versionstamps |

**Platform Support (Server):**
| Platform | Minimum Version |
|----------|-----------------|
| macOS | 15.0+ |
| Linux | Swift 6.2+ |
| Windows | Swift 6.2+ |

> Note: iOS/watchOS/tvOS/visionOS are not supported due to FoundationDB requirements.

## License

MIT License
