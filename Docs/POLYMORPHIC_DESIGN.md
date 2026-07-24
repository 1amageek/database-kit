# Polymorphic Persistence Design

This document defines the intended design for protocol-oriented polymorphic
persistence in `database-kit`, `database-framework`, and downstream packages such
as `swift-memory`.

## Goals

- A polymorphic group is declared once as a Swift protocol.
- Concrete models are persisted by applying `@Persistable` to structs.
- Developers do not write string field names for indexes.
- Shared polymorphic indexes remain type-safe at the declaration site.
- Runtime index maintenance uses the concrete member type, not the first member
  registered in the schema.

## Developer Interface

The public contract is:

```swift
@Polymorphable
public protocol Entity: Polymorphable {
    #Directory<Self>("memory", "entities")

    var label: String { get }
    var entityType: String { get }
    var embedding: [Float] { get set }
    var created: Timestamp { get set }
    var updated: Timestamp { get set }

    #Index(VectorIndexKind<Self>(embedding: \Self.embedding, dimensions: 256))
}

@Persistable
public struct Person: Entity {
    #Directory<Person>("memory", "persons")

    public var id: String
    public var name: String
    public var embedding: [Float]
    public var created: Timestamp
    public var updated: Timestamp

    public var label: String { name }
    public var entityType: String { "person" }
}

@Persistable
public struct Organization: Entity {
    #Directory<Organization>("memory", "organizations")

    public var id: String
    public var name: String
    public var domain: String?
    public var embedding: [Float]
    public var created: Timestamp
    public var updated: Timestamp

    public var label: String { name }
    public var entityType: String { "organization" }
}
```

The concrete models do not write `: Persistable`. The `@Persistable` macro owns
that conformance.

The polymorphic protocol does write `: Polymorphable`. `Polymorphable` itself
must inherit from `Persistable`, so the protocol author does not need to spell
both `Persistable` and `Polymorphable`.

```swift
public protocol Polymorphable: Persistable {
    static var polymorphableType: String { get }
    static var polymorphicDirectoryPathComponents: [any DirectoryPathElement] { get }
    static var polymorphicDirectoryLayer: DirectoryLayer { get }
    static var polymorphicIndexDescriptors: [IndexDescriptor] { get }
}
```

## Swift Macro Constraint

Swift 6.4 does not allow a macro attached to a protocol to add protocol
inheritance by generating an extension with an inheritance clause.

This is invalid Swift:

```swift
protocol Entity {}
extension Entity: Polymorphable {}
```

Therefore this cannot be implemented using the current protocol-based runtime
model:

```swift
@Polymorphable
public protocol Entity {
}
```

The nearest valid interface is:

```swift
@Polymorphable
public protocol Entity: Polymorphable {
}
```

`@Polymorphable` is a metadata and validation macro. It must not be described as
a macro that makes a protocol conform to `Polymorphable`.

There is a second Swift 6.4 frontend limitation: freestanding macros inside a
protocol body can fail during type checking before the attached macro finishes
expansion. This limits which declaration syntax the toolchain accepts; it does
not change the metadata contract. Descriptors are always materialized through
`Self`, never copied from one concrete member.

## Macro Responsibilities

`@Persistable`:

- Applies to concrete structs.
- Generates `Persistable` and `Sendable` conformance.
- Generates field metadata, directory metadata, index descriptors, and static
  adaptation to and from canonical `FieldValue` values.
- Does not generate or require `Codable`. A Native-only application may add
  `Codable` independently for an application-owned external format.

`Polymorphable` protocol:

- Defines the static contract for a polymorphic storage group.
- Inherits from `Persistable`, because every polymorphic member must be
  persistable.
- Supplies defaults only where safe, such as no polymorphic indexes.

`@Polymorphable`:

- Applies only to protocols.
- Validates that the protocol inherits from `Polymorphable`.
- Generates group metadata such as `polymorphableType`,
  `polymorphicDirectoryPathComponents`, `polymorphicDirectoryLayer`, and
  `polymorphicIndexDescriptors`.
- Treats protocol-level indexes as templates that must be materialized for each
  concrete member type.

## Index Declaration Rule

Developer-facing polymorphic index declarations use Swift 6.4 KeyPath syntax
at the macro boundary. String field names are an internal metadata
representation only.

Accepted shape:

```swift
#Index(VectorIndexKind<Self>(embedding: \Self.embedding, dimensions: 256))
```

Rejected developer-facing shape:

```swift
VectorIndexKind(fieldNames: ["embedding"], dimensions: 256)
```

The reason is type safety. KeyPath syntax lets the compiler and macro validate
that the referenced field exists on the protocol or concrete model. The macro
then resolves it to a generated `Field<Model, Value>`. String field names allow
typos and drift, while retaining a runtime KeyPath is incompatible with the
Embedded contract.

## Runtime Descriptor Model

A polymorphic index has one logical name but one concrete descriptor per member
type.

```text
Entity_vector_embedding
  Person       -> Person.fields.embedding
  Organization -> Organization.fields.embedding
  BobTask      -> BobTask.fields.embedding
```

The schema must not build a shared polymorphic descriptor by taking
`memberTypes.first`. Each member receives a descriptor containing that
member's canonical field identity and `FieldSchemaType`.

The schema preserves member-specific descriptors:

```swift
polymorphicDescriptors[
    groupIdentifier: "Entity",
    memberType: Person.self
] = [descriptorWithPersonField]

polymorphicDescriptors[
    groupIdentifier: "Entity",
    memberType: Organization.self
] = [descriptorWithOrganizationField]
```

The group-level metadata may expose logical descriptors for query planning and
client Wire representation, but write maintenance must use the descriptor set
for the actual concrete model being written. Neither level stores a KeyPath.

## Framework Boundary

`database-kit` owns:

- Public declaration model.
- Macro expansion and validation.
- Schema representation of polymorphic groups.
- Member-specific polymorphic descriptor metadata.

`database-framework` owns:

- Runtime directory resolution.
- Dual-write processing.
- Index maintenance.
- Selection of member-specific descriptors during save and delete.

`database-client` owns:

- Typed invocation of the query and schema contracts from `database-kit`.
- Pagination and streaming facades over canonical operation results.
- Transport adaptation and response correlation.

`database-client` consumes polymorphic schema metadata but does not own or
redeclare it. QueryIR and canonical wire-safe schema metadata remain owned by
`database-kit`.

Downstream packages such as `swift-memory` should declare domain protocols and
models using this API. They should not work around polymorphic indexes by
declaring string field names or by manually sharing one concrete generated
field across different member types.

## Required Invariants

- A type saved through a polymorphic group must conform to both `Persistable` and
  `Polymorphable`. This is achieved by `Polymorphable: Persistable`.
- All members of a polymorphic group must agree on each shared index's logical
  name, kind, and compatible field shape.
- Runtime writes must select descriptors by concrete member type.
- A failure to resolve a protocol field for a concrete member is a macro or
  schema-construction error, not a runtime cast or fallback path.
- String field names may exist in serialized metadata, but they are not the
  developer-facing API for declaring indexes.
- Runtime descriptors contain no `KeyPath`, `PartialKeyPath`, `AnyKeyPath`, or
  `Any.Type`.

## Version 1 Contract

`database-kit` enforces the following:

1. `Polymorphable` inherits from `Persistable`.
2. `@Polymorphable` requires explicit `: Polymorphable` inheritance.
3. `Schema` stores descriptors by group identifier and concrete member type.
4. Macro expansion consumes protocol-root KeyPath syntax and emits generated
   fields rooted at each concrete member.
5. Regression tests cover two concrete members, verify that each receives its
   own typed descriptor, and inspect Embedded expansion for retained runtime
   KeyPaths.

`database-framework` must select the descriptor set for the concrete model on
every write and delete. That execution rule is outside this package; no fallback
to the first registered member is part of the contract.
