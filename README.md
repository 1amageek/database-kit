# database-kit

Database semantic models, declarations, QueryIR, and the canonical binary
protocol for the database ecosystem.

## Overview

database-kit is the semantic contract consumed by both
[database-framework](https://github.com/1amageek/database-framework) and
[database-client](https://github.com/1amageek/database-client). Primitive
representations are owned by
[database-types](https://github.com/1amageek/database-types); database-kit adds
model, schema, query, graph, and protocol meaning.

It provides:

- `@Persistable` macro for defining data models
- `@Polymorphable` macro for protocol-oriented polymorphic storage metadata
- `@OWLClass` macro for OWL ontology class mapping (Graph module)
- `@OWLDataProperty` / `@OWLObjectProperty` macros for OWL property annotations (Graph module)
- `IndexKind` protocol for extensible index type definitions
- Foundation-independent identity, RDF, and `QueryIR` semantic models
- canonical binary `DatabaseWire` operations, envelopes, limits, and errors
- opt-in Foundation adapters for Codable values and platform conversions

```
database-client ────────┐
                       ▼
                database-kit ───────▶ database-types
                       ▲
                       │
                database-framework ─▶ storage-kit
```

## Installation

```swift
dependencies: [
    .package(
        url: "https://github.com/1amageek/database-kit.git",
        branch: "main"
    )
]
```

## Modules

| Module | Description |
|--------|-------------|
| `DatabaseValue` | Foundation-independent persisted identity, schema version, and canonical RDF validation/encoding |
| `DatabaseValueCodable` | Optional Codable adaptations for database semantic and primitive values |
| `DatabaseDigest` | Foundation-independent canonical SHA-256 digest support |
| `Core` | `@Persistable` macro, `IndexKind` protocol, schema, and typed model adaptation |
| `DatabaseWire` | Canonical binary envelopes, typed operations, bounded codecs, results, and errors |
| `Vector` | `VectorIndexKind` for similarity search |
| `FullText` | `FullTextIndexKind` for text search |
| `Geospatial` | `SpatialIndexKind` for geospatial queries |
| `Rank` | `RankIndexKind` for leaderboard rankings |
| `Permuted` | `PermutedIndexKind` for alternative field orderings |
| `Graph` | `GraphIndexKind`, OWL ontology types (`OWLOntology`, `OWLClass`, `OWLAxiom`), `@OWLClass` / `@OWLDataProperty` / `@OWLObjectProperty` macros, `OWLClassEntity`, `OWLDataPropertyDescriptor`, `OWLObjectPropertyDescriptor` |
| `GraphMacros` | `@OWLClass` / `@OWLDataProperty` / `@OWLObjectProperty` macro compiler plugins |
| `Relationship` | `RelationshipDescriptor`, delete/cardinality declarations, and `@Relationship` |
| `QueryIR` | Unified query intermediate representation (Expression, SortKey, SelectQuery) |
| `QueryIRFoundation` | Optional Foundation conversions for QueryIR values |
| `DatabaseKit` | Convenience re-export of model, index, relationship, and graph declarations |

`DatabaseValue`, `DatabaseDigest`, `QueryIR`, and `DatabaseWire` build with the
Swift Embedded WASM SDK. `DatabaseValueCodable`, `Core`, macros, and the
declaration modules are standard Swift targets and are not dependencies of the
Embedded client path.

See [Architecture and ownership](Docs/ARCHITECTURE.md) for the package boundary
and dependency rules.

## Quick Start

### Define a Model

```swift
import Core

@Persistable
struct User {
    #Directory<User>("app", "users")
    #Index(ScalarIndexKind<User>(fields: [\.email]), unique: true)
    #Index(ScalarIndexKind<User>(fields: [\.createdAt]))

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
    #Index(ScalarIndexKind<Product>(fields: [\.category, \.price]))
    #Index(ScalarIndexKind<Product>(fields: [\.name]), unique: true)

    var name: String
    var category: String
    var price: Double

    @Transient
    var cachedDescription: String?  // Excluded from persistence
}
```

**Generated code**: `var id`, `persistableType`, `allFields`, `fieldSchemas`, `indexDescriptors`, `Codable`/`Sendable` conformance, dynamic member lookup.

## Polymorphic Persistence

Polymorphic persistence lets multiple concrete `@Persistable` models share a
logical protocol group for storage and querying.

The intended API is:

```swift
@Polymorphable
public protocol Entity: Polymorphable {
    #Directory<Self>("memory", "entities")

    var label: String { get }
    var embedding: [Float] { get set }

    #Index(VectorIndexKind<Self>(embedding: \Self.embedding, dimensions: 256))
}

@Persistable
public struct Person: Entity {
    public var id: String
    public var name: String
    public var embedding: [Float]

    public var label: String { name }
}
```

`@Persistable` owns `Persistable` conformance for concrete structs.
`Polymorphable` inherits from `Persistable`, so a polymorphic protocol only needs
to inherit from `Polymorphable`.

`@Polymorphable` is a metadata and validation macro. Swift 6.4 does not allow an
attached macro on a protocol to add protocol inheritance, so the protocol must
explicitly write `: Polymorphable`.

Swift 6.4 does not type-check freestanding macros in every protocol-body
configuration. `@Polymorphable` still owns the generated metadata contract;
applications must not recreate that metadata with string field names.

Polymorphic indexes must be declared with KeyPaths, not developer-written string
field names. Runtime index maintenance must use descriptors materialized for the
actual concrete member type, not descriptors copied from the first schema member.

See [Polymorphic Persistence Design](Docs/POLYMORPHIC_DESIGN.md) for the full
design and migration plan.

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
ScalarIndexKind<Model>(fields: [\.field1, \.field2])
CountIndexKind<Model>(groupBy: [\.field])
SumIndexKind<Model, Int64>(groupBy: [\.group], value: \.number)
MinIndexKind<Model, Double>(groupBy: [\.group], value: \.number)
MaxIndexKind<Model, Double>(groupBy: [\.group], value: \.number)
AverageIndexKind<Model, Double>(groupBy: [\.group], value: \.number)
VersionIndexKind<Model>(field: \.id, strategy: .keepAll)
BitmapIndexKind<Model>(field: \.status)
TimeWindowLeaderboardIndexKind<Model>(scoreField: \.score, window: .daily)
DistinctIndexKind<Model>(groupBy: [\.group], value: \.member)
PercentileIndexKind<Model, Double>(groupBy: [\.group], value: \.number)
```

### Extended (separate modules)

```swift
VectorIndexKind<Model>(embedding: \.vector, dimensions: 384, metric: .cosine)
FullTextIndexKind<Model>(fields: [\.title, \.body], tokenizer: .simple)
SpatialIndexKind<Model>(latitude: \.latitude, longitude: \.longitude)
RankIndexKind<Model, Int64>(field: \.score)
GraphIndexKind<Model>(from: \.source, edge: \.label, to: \.target)
RDFQuadIndexKind<Model>(subject: \.subject, predicate: \.predicate, object: \.object)
PermutedIndexKind<Model>(
    fields: [\.first, \.second],
    permutation: .swapping(0, 1, size: 2)
)
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

Server-side maintenance is implemented and registered by
[database-framework](https://github.com/1amageek/database-framework). Custom
declarations expose only canonical `IndexKindMetadata`; runtime behavior remains
outside this package.

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
| iOS | 26.0+ |
| macOS | 26.0+ |
| tvOS | 26.0+ |
| watchOS | 26.0+ |
| visionOS | 26.0+ |
| Linux | Swift 6.4+ |
| WASI Embedded | Swift 6.4+ for `DatabaseValue`, `DatabaseDigest`, `QueryIR`, and `DatabaseWire` |

## Related Packages

| Package | Role | Platform |
|---------|------|----------|
| **[database-types](https://github.com/1amageek/database-types)** | Primitive field-value algebra and immutable byte ownership | Embedded, Apple, Linux |
| **[database-framework](https://github.com/1amageek/database-framework)** | Database execution, transactions, indexes, graph, ontology, and validation | WASI, macOS, Linux |
| **[database-client](https://github.com/1amageek/database-client)** | Typed invocation and JavaScript, HTTP, and WebSocket transports | Embedded, Apple, Linux |
| **[storage-kit](https://github.com/1amageek/storage-kit)** | Storage transactions and backend adapters | WASI, macOS, Linux |

## License

MIT License
