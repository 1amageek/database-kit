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

The desired public shape is:

```swift
@Polymorphable
public protocol Entity: Polymorphable {
    #Directory<Entity>("memory", "entities")

    var label: String { get }
    var entityType: String { get }
    var embedding: [Float] { get set }
    var created: Date { get set }
    var updated: Date { get set }
}

@Persistable
public struct Person: Entity {
    #Directory<Person>("memory", "persons")

    public var id: String
    public var name: String
    public var embedding: [Float]
    public var created: Date
    public var updated: Date

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
    public var created: Date
    public var updated: Date

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

Swift 6.3 does not allow a macro attached to a protocol to add protocol
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

## Macro Responsibilities

`@Persistable`:

- Applies to concrete structs.
- Generates `Persistable`, `Codable`, and `Sendable` conformance.
- Generates field metadata, directory metadata, index descriptors, and coding
  support.

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

Developer-facing polymorphic index declarations must remain KeyPath based.
String field names are an internal metadata representation only.

Accepted shape:

```swift
#Index<Entity>(VectorIndexKind<Entity>(embedding: \.embedding, dimensions: 256))
```

Rejected developer-facing shape:

```swift
VectorIndexKind(fieldNames: ["embedding"], dimensions: 256)
```

The reason is type safety. KeyPath declarations let the compiler validate that
the referenced field exists on the protocol or concrete model. String field
names allow typos and drift.

## Runtime Descriptor Model

A polymorphic index has one logical name but one concrete descriptor per member
type.

```text
Entity_vector_embedding
  Person       -> \Person.embedding
  Organization -> \Organization.embedding
  BobTask      -> \BobTask.embedding
```

The schema must not build a shared polymorphic descriptor by taking
`memberTypes.first`. A descriptor containing `\Person.embedding` is not valid for
`Organization` or `BobTask`.

The schema should preserve member-specific descriptors:

```swift
polymorphicDescriptors[
    groupIdentifier: "Entity",
    memberType: Person.self
] = [descriptorWithPersonKeyPath]

polymorphicDescriptors[
    groupIdentifier: "Entity",
    memberType: Organization.self
] = [descriptorWithOrganizationKeyPath]
```

The group-level metadata may expose logical descriptors for query planning and
client wire format, but write maintenance must use the descriptor set for the
actual concrete model being written.

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

- Client-facing query builders.
- Wire-safe polymorphic group metadata.
- Decoding of mixed concrete results using schema metadata.

Downstream packages such as `swift-memory` should declare domain protocols and
models using this API. They should not work around polymorphic indexes by
declaring string field names or by manually sharing one concrete KeyPath across
different member types.

## Required Invariants

- A type saved through a polymorphic group must conform to both `Persistable` and
  `Polymorphable`. This is achieved by `Polymorphable: Persistable`.
- All members of a polymorphic group must agree on each shared index's logical
  name, kind, and compatible field shape.
- Runtime writes must select descriptors by concrete member type.
- A KeyPath cast failure during index maintenance is a bug signal, not a normal
  fallback path.
- String field names may exist in serialized metadata, but they are not the
  developer-facing API for declaring indexes.

## Migration Direction

1. Change `Polymorphable` to inherit from `Persistable`.
2. Update `@Polymorphable` documentation and diagnostics to require explicit
   `: Polymorphable`.
3. Replace schema construction that uses only the first member type with
   member-specific descriptor storage.
4. Update `database-framework` dual-write index maintenance to request
   descriptors for the concrete model type.
5. Update `swift-memory` to declare the `Entity` group through the protocol-level
   API and remove any workaround that relies on string field names or first
   member descriptors.
6. Add regression tests with at least two concrete members in the same group and
   verify writes for the non-first member.
