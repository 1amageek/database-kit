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
         AuthContext
             │
             ▼
database-framework evaluation
             │
      ┌──────┴──────┐
      ▼             ▼
SecurityPolicy   restrictedFieldsMetadata
```

## Owned Types

| Type | Contract |
|---|---|
| `AuthContext` | Application-defined authenticated subject and roles |
| `SecurityPolicy` | Per-model allow/deny decisions |
| `SecurityQuery<Model>` | Bounded query shape presented to list authorization |
| `FieldAccessLevel` | Static public, authenticated, or role-based field policy |
| `Restricted<Value>` | Field declaration wrapper whose policy is immutable |
| `RestrictedFieldMetadata` | Macro-generated static field policy |

## Authentication Boundary

An application creates `AuthContext` only after validating credentials. The
database runtime must treat a supplied context as identity data, not as proof
that authentication occurred.

```swift
struct RequestIdentity: AuthContext {
    let userID: String
    let roles: Set<String>
}
```

An unauthenticated request is represented by `nil`. Empty roles do not imply an
administrator.

## Model Policy

`SecurityPolicy` is deny-by-default. A model opts into each allowed operation
explicitly.

```swift
extension Post: SecurityPolicy {
    static func allowGet(
        resource: Post,
        auth: (any AuthContext)?
    ) -> Bool {
        resource.isPublic || resource.authorID == auth?.userID
    }

    static func allowList(
        query: SecurityQuery<Post>,
        auth: (any AuthContext)?
    ) -> Bool {
        guard auth != nil, let limit = query.limit else {
            return false
        }
        return limit <= 100
    }

    static func allowCreate(
        newResource: Post,
        auth: (any AuthContext)?
    ) -> Bool {
        newResource.authorID == auth?.userID
    }

    static func allowUpdate(
        resource: Post,
        newResource: Post,
        auth: (any AuthContext)?
    ) -> Bool {
        resource.authorID == auth?.userID
            && newResource.authorID == resource.authorID
    }

    static func allowDelete(
        resource: Post,
        auth: (any AuthContext)?
    ) -> Bool {
        resource.authorID == auth?.userID
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

`@Persistable` generates `restrictedFieldsMetadata`. Runtime evaluation uses
that static metadata; policies are not serialized with field values and are not
reconstructed from persisted data.

`Restricted` deliberately has no standalone `Codable` conformance. Decoding a
wrapper without its declaring model cannot recover the policy and must not
silently replace it with `.public`.

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
| Get | `allowGet` before returning the model |
| List | `allowList` before query execution |
| Create | `allowCreate` inside the mutation transaction |
| Update | `allowUpdate` with old and new values inside one transaction |
| Delete | `allowDelete` before deletion inside the transaction |
| Field read | Apply generated read metadata before returning data |
| Field write | Validate generated write metadata before commit |

Authorization failure is an explicit typed failure. It must not become an empty
page, a missing object, a masked write, or a retryable transport error.

## Isolation

Authorization and storage partitioning solve different problems.

| Mechanism | Purpose |
|---|---|
| `SecurityPolicy` / `Restricted` | Decide whether an authenticated subject may perform an operation |
| `#Directory(..., layer: .partition)` | Declare logical partition identity |
| storage/runtime transaction isolation | Enforce physical and transactional boundaries |

Applications that require tenant isolation should use both authorization and
partition identity. Neither one substitutes for the other.
