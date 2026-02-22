# database-kit

Platform-independent model definitions and index type specifications for the database ecosystem.

## Overview

database-kit is the **shared foundation** used by both server ([database-framework](https://github.com/1amageek/database-framework)) and client ([database-client](https://github.com/1amageek/database-client)). It provides:

- `@Persistable` macro for defining data models
- `@OWLClass` macro for OWL ontology class mapping (Graph module)
- `@OWLDataProperty` / `@OWLObjectProperty` macros for OWL property annotations (Graph module)
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
| `Graph` | `GraphIndexKind`, OWL ontology types (`OWLOntology`, `OWLClass`, `OWLAxiom`), `@OWLClass` / `@OWLDataProperty` / `@OWLObjectProperty` macros, `OWLClassEntity`, `OWLDataPropertyDescriptor`, `OWLObjectPropertyDescriptor` |
| `GraphMacros` | `@OWLClass` / `@OWLDataProperty` / `@OWLObjectProperty` macro compiler plugins |
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

## Ontology Integration

Ontology features are in the **Graph** module. Three usage levels can be combined incrementally.

| Level | Components | Use Case |
|-------|-----------|----------|
| **1. OntologyStore** | `OWLOntology`, `context.ontology` API | OWL reasoning, class hierarchy, property chain evaluation |
| **2. Macros + OntologyStore** | Level 1 + `@OWLClass`, `@OWLObjectProperty`, `@OWLDataProperty` | Bind Persistable types to OWL concepts, IRI validation, SPARQL over tables |
| **3. Macros + OntologyStore + Triples** | Level 2 + `GraphIndexKind` triple store | SPARQL federation across Persistable tables and RDF triples |

### Level 1: OntologyStore

Define and load OWL ontologies for reasoning and hierarchy queries. No macros required.

```swift
var ontology = OWLOntology(iri: "http://example.org/onto")
ontology.classes = [OWLClass(iri: "ex:Person"), OWLClass(iri: "ex:Employee")]
ontology.axioms = [.subClassOf(sub: .named("ex:Employee"), sup: .named("ex:Person"))]

// Load and query (server-side, database-framework)
try await context.ontology.load(ontology)
let reasoner = try await context.ontology.reasoner(for: "http://example.org/onto")
let superClasses = reasoner.superClasses(of: "ex:Employee")
```

### Level 2: Macros + OntologyStore

Bind Persistable types to OntologyStore concepts. **Macros are bindings, not definitions** — class hierarchies, property characteristics, and axioms live in the OntologyStore. Each row is interpreted as virtual RDF triples, enabling SPARQL queries over Persistable tables.

```swift
@Persistable
@OWLClass("ex:Employee")
struct Employee {
    @OWLDataProperty("ex:name")
    var name: String

    @OWLDataProperty("ex:worksFor", to: \Department.id, functional: true)
    var departmentID: String?
}

@Persistable
@OWLObjectProperty("ex:employs", from: "employeeID", to: "projectID")
struct Assignment {
    var id: String = UUID().uuidString
    var employeeID: String = ""
    var projectID: String = ""

    @OWLDataProperty("ex:since")
    var startDate: Date = Date()
}
```

IRI validation checks that macro bindings reference valid OntologyStore entries:

```swift
try await context.ontology.validateSchema(schema, ontologyIRI: "http://example.org/onto")
```

SPARQL queries Persistable tables directly:

```swift
let results = try await context.sparql()
    .from(Employee.self)
    .where("?e", "rdf:type", "ex:Employee")
    .where("?e", "ex:name", "?name")
    .select("?e", "?name")
    .execute()
```

### Level 3: Macros + OntologyStore + Triples

Add a GraphIndex triple store alongside Persistable tables. SPARQL federation resolves each triple pattern to the optimal source — structured data in tables, unstructured knowledge in triples:

```swift
let results = try await context.sparql()
    .from(RDFTriple.self)        // Triple store
    .from(Employee.self)          // Persistable table
    .where("?e", "rdf:type", "ex:Employee")     // → Employee table
    .where("?e", "ex:worksFor", "?dept")         // → Employee table
    .where("?dept", "ex:locatedIn", "?city")     // → Triple store
    .select("?e", "?city")
    .execute()
```

### Macro Reference

**`@OWLClass(_ iri: String)`** — Maps a Persistable type to an OWL class. Generates `OWLClassEntity` conformance, `ontologyClassIRI`, and `ontologyPropertyDescriptors`.

**`@OWLObjectProperty(_ iri: String, from: String, to: String)`** — Maps a Persistable type to an OWL ObjectProperty with endpoint fields. Generates `OWLObjectPropertyEntity` conformance and a `GraphIndexKind.adjacency` index.

**`@OWLDataProperty(_ iri: String, ...)`** — Annotates a field with an OWL datatype property IRI.

Bare names (without `:`, `#`, or `/`) default to the namespace extracted from the parent `@OWLClass` or `@OWLObjectProperty` IRI.

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
