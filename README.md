# database-kit

Platform-independent model definitions and index type specifications for the database ecosystem.

## Overview

database-kit is the **shared foundation** used by both server ([database-framework](https://github.com/1amageek/database-framework)) and client ([database-client](https://github.com/1amageek/database-client)). It provides:

- `@Persistable` macro for defining data models
- `IndexKind` protocol for extensible index type definitions
- `QueryIR` for a unified query intermediate representation
- Protobuf-compatible serialization

```
┌──────────────────────────────────────────────────────────┐
│                      database-kit                        │
│  @Persistable models, IndexKind protocols, QueryIR       │
└──────────┬───────────────────────────────┬───────────────┘
           │                               │
           ▼                               ▼
┌─────────────────────┐       ┌─────────────────────────┐
│  database-framework │       │    database-client       │
│  Server execution   │◄─────│    Client SDK            │
│  FoundationDB       │  WS  │    iOS / macOS           │
└─────────────────────┘       └─────────────────────────┘
```

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/database-kit.git", from: "26.0207.0")
]
```

## Modules

| Module | Description |
|--------|-------------|
| `Core` | `@Persistable` macro, `IndexKind` protocol, Schema, Protobuf serialization |
| `Vector` | `VectorIndexKind` for similarity search |
| `FullText` | `FullTextIndexKind` for text search |
| `Spatial` | `SpatialIndexKind` for geospatial queries |
| `Rank` | `RankIndexKind` for leaderboard rankings |
| `Permuted` | `PermutedIndexKind` for alternative field orderings |
| `Graph` | `AdjacencyIndexKind` / `TripleIndexKind` for graph relationships |
| `Relationship` | `RelationshipIndexKind` and `@Relationship` macro |
| `QueryIR` | Unified query intermediate representation (Expression, SortKey, SelectQuery) |
| `DatabaseClientProtocol` | Shared protocol for client-server communication |
| `DatabaseKit` | All-in-one re-export |

## Quick Start

### Define a Model

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

### Schema

```swift
let schema = Schema(
    entities: [
        Schema.Entity(from: User.self),
        Schema.Entity(from: Product.self),
    ],
    version: Schema.Version(1, 0, 0)
)
```

## @Persistable Macro

The `@Persistable` macro generates all required protocol conformances:

```swift
@Persistable
struct Product {
    #Index<Product>(ScalarIndexKind(fields: [\.category, \.price]))
    #Index<Product>(ScalarIndexKind(fields: [\.name]), unique: true)

    var name: String
    var category: String
    var price: Double

    @Transient
    var cachedDescription: String?  // Excluded from persistence
}
```

**Generated code**: `var id`, `persistableType`, `allFields`, `fieldSchemas`, `indexDescriptors`, `Codable`/`Sendable` conformance, dynamic member lookup.

## #Directory Macro

### Static Path

```swift
#Directory<User>("app", "users")
```

### Multi-tenant Partitioning

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
    var accountID: String
    var channelID: String
    var content: String
}
```

## Built-in Index Kinds

### Standard (Core module)

```swift
ScalarIndexKind<T>(fields: [\.field1, \.field2])     // Range queries and sorting
CountIndexKind<T>(groupBy: [\.field])                // Count aggregation
SumIndexKind<T, V>(groupBy: [\.group], value: \.num) // Sum aggregation
MinIndexKind<T, V>(groupBy: [\.group], value: \.num) // Minimum tracking
MaxIndexKind<T, V>(groupBy: [\.group], value: \.num) // Maximum tracking
AverageIndexKind<T, V>(groupBy: [\.g], value: \.num) // Average calculation
VersionIndexKind<T>(field: \.id, strategy: .keepAll)  // Version history
BitmapIndexKind<T>(field: \.status)                   // Low-cardinality bitmap
TimeWindowLeaderboardIndexKind<T, S>(scoreField: \.score, window: .daily)
```

### Extended (separate modules)

```swift
VectorIndexKind<T>(embedding: \.vec, dimensions: 384, metric: .cosine)
FullTextIndexKind<T>(content: \.body, language: .english)
SpatialIndexKind<T>(latitude: \.lat, longitude: \.lng)
RankIndexKind<T, S>(field: \.score)
TripleIndexKind<T>(subject: \.s, predicate: \.p, object: \.o)
AdjacencyIndexKind<T>(from: \.source, edge: \.label, to: \.target)
PermutedIndexKind<T>(fields: [\.a, \.b])
RelationshipIndexKind<T, R>(foreignKey: \.customerId, relatedFields: [\.name])
```

## Custom Index Kinds

Third parties can create custom index types by conforming to `IndexKind`:

```swift
import Core

public struct TimeSeriesIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "com.mycompany.timeseries" }
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    public let fieldNames: [String]
    public let resolution: TimeResolution

    public enum TimeResolution: String, Codable, Sendable {
        case second, minute, hour, day
    }

    public init(
        fields: [PartialKeyPath<Root>],
        resolution: TimeResolution = .minute
    ) {
        self.fieldNames = fields.map { Root.fieldName(for: $0) }
        self.resolution = resolution
    }
}
```

Server-side maintenance is implemented in [database-framework](https://github.com/1amageek/database-framework) via `IndexKindMaintainable`.

## PersistableEnum

```swift
enum Status: String, PersistableEnum {
    case active, inactive, pending
}

@Persistable
struct Task {
    var title: String
    var status: Status = .pending
}
```

## @Relationship Macro

```swift
@Persistable
struct Order {
    var total: Double

    @Relationship(Customer.self, indexFields: [\.name])
    var customerID: String?
}
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

## Related Packages

| Package | Role | Platform |
|---------|------|----------|
| **[database-framework](https://github.com/1amageek/database-framework)** | Server-side index maintenance on FoundationDB | macOS, Linux |
| **[database-client](https://github.com/1amageek/database-client)** | Client SDK with KeyPath queries and WebSocket transport | iOS, macOS |

## License

MIT License
