# database-kit

Database semantic models, declarations, QueryIR, and the canonical binary
protocol for the database ecosystem.

The normative ownership and product contract is documented in
[database-kit Responsibility Specification](Docs/DATABASE_KIT_SPECIFICATION.md).

The version 1 architecture migration is in progress. Product declarations or
Native tests alone are not evidence that the Embedded and zero-copy acceptance
gates have passed.

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
- `@OWLClass` macro for OWL ontology class mapping
- `@OWLDataProperty` / `@OWLObjectProperty` macros for OWL property annotations
- `IndexKind` protocol for extensible index type definitions
- Foundation-independent identity, RDF, and `QueryIR` semantic models
- canonical binary `DatabaseWire` operations, envelopes, limits, and errors
- one Foundation-independent semantic module
- one canonical bounded binary protocol module
- one optional native Foundation model-integration module

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
| `DatabaseKit` | Foundation-independent model, identity, schema, query, mutation, relationship, index, graph, ontology, and SHACL declarations |
| `DatabaseWire` | Canonical binary envelopes, typed operations, bounded encoding and decoding, results, errors, and internal digest support |
| `DatabaseKitFoundation` | Native-only participation of Foundation scalar types in `Persistable` field adaptation |

Relationship, vector, full-text, geographic, rank, permutation, graph,
ontology, and SHACL are source classifications within `DatabaseKit`, not
separate products.

`DatabaseKit` and `DatabaseWire` are required to build with the matching Swift
Embedded WASM SDK before the version 1 implementation is complete.
`DatabaseKitFoundation` is excluded from that dependency graph.

There is no umbrella value module in database-kit. `FieldValue` and every
primitive alternative are defined only by `DatabaseTypes`; the database-kit
modules above add model, RDF, SHACL, query, and protocol semantics without
redeclaring that algebra.

Query pagination uses `UInt64`, so negative `LIMIT` and `OFFSET` values are not
representable. DatabaseWire encoding measures the exact frame and writes
directly into one final `ByteString` allocation; there is no public
mutable-array writer path.

See [Architecture and ownership](Docs/ARCHITECTURE.md) for the package boundary
and dependency rules.
See
[Zero-Copy and Embedded Architecture](Docs/ZERO_COPY_EMBEDDED_DESIGN.md) for
the copy budget, static model-adaptation design, lazy result pages, and WASM
host transport contract.

## Verification

| Contract | Verification |
|---|---|
| Apple platform behavior | `xcodebuild test` for the package scheme |
| Embedded client graph | Release build of `DatabaseWire` with the Swift 6.4 Embedded WASM SDK |
| Full semantic graph | Release build of the `DatabaseKit` product with the Swift 6.4 Embedded WASM SDK |
| Binary ownership | Tests assert that payload pages borrow ranges from the single final frame allocation |
| Decoder safety | Tests cover truncation, limits, malformed values, non-canonical input, and cyclic RDF lists |

## Quick Start

### Define a Model

```swift
import DatabaseKit

@Persistable
struct User {
    #Directory<User>("app", "users")
    #Index(.scalar, fields: [\User.email], unique: true)
    #Index(.scalar, fields: [\User.createdAt])

    var id: String
    var email: String
    var name: String
    var createdAt: Timestamp
}
```

### Schema

```swift
let schema = try Schema(
    entities: [
        try User.schemaEntity,
        try Product.schemaEntity,
    ],
    version: Schema.Version(1, 0, 0)
)
```

## @Persistable Macro

The `@Persistable` macro generates all required protocol conformances:

```swift
@Persistable
struct Product {
    #Index(
        .scalar,
        fields: [\Product.category, \Product.price]
    )
    #Index(.scalar, fields: [\Product.name], unique: true)

    var id: String
    var name: String
    var category: String
    var price: Double

    @Transient
    var cachedDescription: String?  // Excluded from persistence
}
```

**Generated code**: `persistableType`, `allFields`, `fieldSchemas`, typed
`fields`, `indexDescriptors`, concrete `PersistedFieldOutput` traversal,
canonical decoding, and `Sendable` conformance. The model declares `id` and
owns its generation policy.

The production encoder does not inspect a model through `Mirror`, `Any`, or a
runtime metatype. It writes each concrete property directly to the selected
output. `PersistableFieldEncoder.encode(_:)` is the explicit owned
materializer for callers that require `[PersistableField]`; Wire and storage
outputs can consume the generated traversal without that intermediate array.

## Polymorphic Persistence

Polymorphic persistence lets multiple concrete `@Persistable` models share a
logical protocol group for storage and querying.

The intended API is:

```swift
@Polymorphable
public protocol Entity: Polymorphable {
    #Directory<Self>("memory", "entities")

    var label: String { get }
    var embedding: Vector { get set }

    #PolymorphicIndex(
        .vector(dimensions: 256),
        embedding: "embedding"
    )
}

@Persistable
public struct Person: Entity {
    public var id: String
    public var name: String
    public var embedding: Vector

    public var label: String { name }
}
```

`@Persistable` owns `Persistable` conformance for concrete structs.
`Polymorphable` inherits from `Persistable`, so a polymorphic protocol only needs
to inherit from `Polymorphable`.

`@Polymorphable` is a metadata and validation macro. Swift 6.4 does not allow an
attached macro on a protocol to add protocol inheritance, so the protocol must
explicitly write `: Polymorphable`.

Swift 6.4 cannot form a `KeyPath<Self, Value>` while the protocol containing
the declaration is still being defined. Protocol-level indexes therefore use
logical property names with the dedicated `#PolymorphicIndex` macro.
`@Polymorphable` validates every name against a declared protocol property at
compile time. `Schema` then resolves the logical property to each concrete
member's generated `FieldIdentity` and validates its canonical field type.

This string boundary is limited to protocol source declarations. Concrete
models continue to use KeyPath syntax with `#Index`, and runtime index
maintenance receives only concrete field identities. It performs neither
KeyPath retention nor string-to-field discovery.

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
    #Directory<Order>("tenants", \Order.accountID, "orders", layer: .partition)

    var orderID: Int64
    var accountID: String  // Partition key
}
```

### Multi-level Partitioning

```swift
@Persistable
struct Message {
    #Directory<Message>(
        "tenants", \Message.accountID,
        "channels", \Message.channelID,
        "messages",
        layer: .partition
    )

    var messageID: String
    var accountID: String
    var channelID: String
    var content: String
}
```

## Built-in Index Kinds

Built-in indexes have one declaration surface: `IndexDefinition` through
`#Index`. The generic `*IndexKind<Model>` duplicates are not part of version 1.

```swift
@Persistable
struct Event {
    #Index(
        .scalar,
        fields: [\Event.calendarID, \Event.startsAt]
    )
    #Index(.count, groupBy: [\Event.calendarID])
    #Index(
        .sum,
        groupBy: [\Event.calendarID],
        value: \Event.attendeeCount
    )
    #Index(
        .version(strategy: .keepAll),
        field: \Event.id
    )
    #Index(
        .vector(dimensions: 384, metric: .cosine),
        embedding: \Event.embedding
    )
    #Index(
        .fullText(tokenizer: .simple),
        fields: [\Event.title, \Event.description]
    )
    #Index(.spatial(), location: \Event.location)
    #Index(.rank(), field: \Event.attendeeCount)

    var id: String
    var calendarID: String
    var startsAt: Timestamp
    var attendeeCount: Int64
    var embedding: Vector
    var title: String
    var description: String
    var location: GeographicPoint
}
```

The enclosing macro consumes each KeyPath and emits the corresponding
generated field identity. Protocol-level polymorphic declarations use
logical property names, which `@Polymorphable` verifies against protocol
properties.
Neither runtime path retains a KeyPath.

## Custom Index Kinds

`IndexKind` is reserved for RDF, OWL, and third-party extension semantics that
are not built into `IndexDefinition`:

```swift
import DatabaseKit

public struct TimeSeriesIndexKind<Root: Persistable>: IndexKind {
    public static var identifier: String { "com.mycompany.timeseries" }
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    public let indexFields: [IndexField<Root>]
    public let resolution: TimeResolution

    public var indexName: String {
        "\(Root.persistableType)_timeseries_\(fieldNames.joined(separator: "_"))"
    }

    public var metadata: [String: FieldValue] {
        ["resolution": .string(resolution.rawValue)]
    }

    public enum TimeResolution: String, Sendable, Hashable {
        case second, minute, hour, day
    }

    public init(
        fields: [IndexField<Root>],
        resolution: TimeResolution = .minute
    ) {
        self.indexFields = fields
        self.resolution = resolution
    }

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
        guard fields[0].type == .timestamp, !fields[0].isArray else {
            throw .unsupportedField(
                index: identifier,
                field: fields[0],
                reason: "Time-series fields must use timestamp values"
            )
        }
    }
}
```

Application use passes a generated field through the custom descriptor path:

```swift
let timeSeries = try IndexDescriptor(
    name: "Event_timeseries_startsAt",
    kind: TimeSeriesIndexKind<Event>(
        fields: [Event.fields.startsAt.ascending],
        resolution: .minute
    )
)

let schema = try Schema(
    entities: [
        try Schema.Entity(
            from: Event.self,
            including: [timeSeries]
        )
    ]
)
```

Server-side maintenance is implemented and registered by
[database-framework](https://github.com/1amageek/database-framework). Custom
declarations expose only canonical `IndexKindMetadata`; runtime behavior remains
outside this package. `IndexDescriptor` validates concrete generated fields and
configuration before `Schema` exposes the catalog.

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
| **3. Macros + OntologyStore + Triples** | Level 2 + graph and RDF index declarations | SPARQL federation across Persistable tables and RDF triples |

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
    var startDate: Timestamp
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

**`@OWLObjectProperty(_ iri: String, from: String, to: String)`** — Maps a Persistable type to an OWL ObjectProperty with endpoint fields. Generates `OWLObjectPropertyEntity` conformance and an adjacency graph index declaration with an implicit label.

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
| WASI Embedded | Swift 6.4+ for `DatabaseKit` and `DatabaseWire` |
| WASI (standard runtime) | Swift 6.4+ for the same semantic and wire products |

## Related Packages

| Package | Role | Platform |
|---------|------|----------|
| **[database-types](https://github.com/1amageek/database-types)** | Primitive field-value algebra and immutable byte ownership | Embedded, Apple, Linux |
| **[database-framework](https://github.com/1amageek/database-framework)** | Database execution, transactions, indexes, graph, ontology, and validation | WASI, macOS, Linux |
| **[database-client](https://github.com/1amageek/database-client)** | Typed invocation and WASM host, HTTP, and WebSocket transports | Embedded, Apple, Linux |
| **[storage-kit](https://github.com/1amageek/storage-kit)** | Storage transactions and backend adapters | WASI, macOS, Linux |

## License

MIT License
