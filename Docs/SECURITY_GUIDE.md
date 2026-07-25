# Security Declaration Contract

## Scope

`database-kit` defines storage-independent authorization declarations. It does
not authenticate requests, install task-local state, execute queries, mask
fields, or coordinate transactions. Those responsibilities belong to the
application boundary and `database-framework`.

```text
validated application identity
             │
             ▼
  AuthorizationContext
             │
             ▼
typed database-framework policy registry
             │
      ┌──────┴──────┐
      ▼             ▼
SecurityPolicy   Schema.Entity.fieldAccessRules
```

## Owned Types

| Type | Contract |
|---|---|
| `Principal` | Validated subject identifier, roles, and canonical claims |
| `AuthorizationContext` | Concrete anonymous or authenticated request state |
| `SecurityPolicy` | Per-model allow/deny decisions |
| `SecurityQuery` | Bounded query shape presented to list authorization |
| `FieldAccessLevel` | Static public, authenticated, or role-based field policy |
| `Restricted<Value>` | Lightweight field annotation wrapper |
| `FieldAccessRule` | Macro-generated static field policy bound to `FieldIdentity` |

## Authentication Boundary

An application creates a `Principal` only after validating credentials. The
database runtime treats a supplied principal as identity data, not as proof
that authentication occurred.

```swift
let context = AuthorizationContext.authenticated(
    Principal(
        identifier: subject,
        roles: verifiedRoles,
        claims: verifiedClaims
    )
)
```

An unauthenticated request is represented by `.anonymous`, not by `nil`.
`AuthorizationContext` is a concrete value and can therefore cross the
Embedded model and policy boundary without existential storage. Empty roles do
not imply an administrator.

## Model Policy

`SecurityPolicy` is deny-by-default. A model opts into each allowed operation
explicitly.

```swift
extension Post: SecurityPolicy {
    static func permitsRead(
        of resource: borrowing Post,
        in context: borrowing AuthorizationContext
    ) -> Bool {
        resource.isPublic
            || resource.authorID == context.principal?.identifier
    }

    static func permitsQuery(
        _ query: borrowing SecurityQuery,
        in context: borrowing AuthorizationContext
    ) -> Bool {
        guard context.isAuthenticated, let limit = query.limit else {
            return false
        }
        return limit <= 100
    }

    static func permitsCreate(
        _ newResource: borrowing Post,
        in context: borrowing AuthorizationContext
    ) -> Bool {
        newResource.authorID == context.principal?.identifier
    }

    static func permitsUpdate(
        from resource: borrowing Post,
        to newResource: borrowing Post,
        in context: borrowing AuthorizationContext
    ) -> Bool {
        resource.authorID == context.principal?.identifier
            && newResource.authorID == resource.authorID
    }

    static func permitsDelete(
        _ resource: borrowing Post,
        in context: borrowing AuthorizationContext
    ) -> Bool {
        resource.authorID == context.principal?.identifier
    }
}
```

List authorization validates the requested query. It is not a row filter. A
runtime must reject a disallowed query instead of returning a partial successful
result.

## Field Policy

Field policies are part of the model declaration.

```swift
@Persistable
struct Employee {
    @Restricted(
        read: .roles(["hr", "manager"]),
        write: .roles(["hr"])
    )
    var salary: Double = 0

    @Restricted(read: .authenticated)
    var internalNotes: String = ""
}
```

`@Persistable` generates `fieldAccessRules`. `Schema.Entity` validates and
retains those rules with the exact field name and field number. Policies are
not serialized with field values and are not reconstructed from persisted
data.

`Restricted` stores only its wrapped value. Read and write declarations exist
once in the static schema instead of being duplicated in every model instance.
It deliberately has no standalone `Codable` conformance.

`FieldAccessLevel` contains only deterministic, comparable declarations:

- `.public`
- `.authenticated`
- `.roles(Set<String>)`

Model-specific predicates belong in `SecurityPolicy`. Closure-backed access
levels cannot provide stable equality, schema metadata, or wire semantics.

## Runtime Requirements

`database-framework` must enforce these declarations on the real operation
path:

| Operation | Required evaluation |
|---|---|
| Read | `permitsRead` before returning the model |
| Query | `permitsQuery` before query execution |
| Create | `permitsCreate` inside the mutation transaction |
| Update | `permitsUpdate` with old and new values inside one transaction |
| Delete | `permitsDelete` before deletion inside the transaction |
| Field read | Project authorized fields at the result boundary |
| Field write | Validate changed canonical field values before commit |

Authorization failure is an explicit typed failure. It must not become an empty
page, a missing object, a default-valued model, a masked write, or a retryable
transport error.

`database-framework` registers each concrete `SecurityPolicy` through generic
application runtime composition. DatabaseKit does not expose type-erased policy
entry points, accept `any Persistable`, or recover policy conformance with a
runtime cast.

## Isolation

Authorization and storage partitioning solve different problems.

| Mechanism | Purpose |
|---|---|
| `SecurityPolicy` / `Restricted` | Decide whether an authenticated subject may perform an operation |
| `#Directory(..., layer: .partition)` | Declare logical partition identity |
| storage/runtime transaction isolation | Enforce physical and transactional boundaries |

Applications that require tenant isolation should use both authorization and
partition identity. Neither one substitutes for the other.
