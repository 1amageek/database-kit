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
| `Core` | Persistable protocol, @Persistable macro, Schema, Serialization |
| `Vector` | VectorIndexKind for similarity search |
| `FullText` | FullTextIndexKind for text search |
| `Spatial` | SpatialIndexKind for geospatial queries |
| `Rank` | RankIndexKind for leaderboards |
| `Permuted` | PermutedIndexKind for alternative field orderings |
| `Graph` | AdjacencyIndexKind for graph relationships |
| `DatabaseKit` | All-in-one re-export (individual imports recommended) |

## Quick Start

```swift
import Core

@Persistable
struct User {
    #Directory<User>("app", "users")
    #Index<User>([\.email], unique: true)
    #Index<User>([\.createdAt])

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
    #PrimaryKey<Order>([\.orderID])

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

    var messageID: Int64
    var accountID: String  // First partition key
    var channelID: String  // Second partition key
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

    /// Validate whether this index kind supports specified types
    static func validateTypes(_ types: [Any.Type]) throws
}
```

### Built-in Index Kinds

```swift
// Standard indexes (in Core module)
ScalarIndexKind()      // VALUE index for sorting and range queries
CountIndexKind()       // Count aggregation
SumIndexKind()         // Sum aggregation
MinIndexKind()         // Minimum value tracking
MaxIndexKind()         // Maximum value tracking
VersionIndexKind()     // Version history tracking

// Extended indexes (separate modules)
VectorIndexKind(...)   // Vector similarity search
FullTextIndexKind(...) // Full-text search
SpatialIndexKind(...)  // Geospatial queries
RankIndexKind()        // Leaderboard rankings
```

## Creating Custom Index Kinds

Third parties can create custom index types by conforming to `IndexKind`:

```swift
import Core

/// Custom time-series index for efficient time-range queries
public struct TimeSeriesIndexKind: IndexKind {
    public static let identifier = "com.mycompany.timeseries"
    public static let subspaceStructure = SubspaceStructure.hierarchical

    public let resolution: TimeResolution
    public let retention: TimeInterval?

    public enum TimeResolution: String, Codable, Sendable {
        case second, minute, hour, day
    }

    public init(resolution: TimeResolution = .minute, retention: TimeInterval? = nil) {
        self.resolution = resolution
        self.retention = retention
    }

    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.count >= 1 else {
            throw IndexTypeValidationError.insufficientFields(
                expected: 1, actual: types.count
            )
        }
        // First field must be Date
        guard types[0] == Date.self else {
            throw IndexTypeValidationError.typeMismatch(
                field: "timestamp",
                expected: "Date",
                actual: String(describing: types[0])
            )
        }
    }
}

// Usage
@Persistable
struct SensorReading {
    #Index<SensorReading>([\.timestamp, \.sensorId],
                          type: TimeSeriesIndexKind(resolution: .second))

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

    #Index<Product>([\.category, \.price])
    #Index<Product>([\.name], unique: true)

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
- `static var indexDescriptors: [IndexDescriptor]`
- `Codable`, `Sendable` conformances
- Dynamic member lookup support

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
- **FDBContainer**: SwiftData-like container management
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
