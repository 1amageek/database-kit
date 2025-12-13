# Security Guide

このガイドでは、DatabaseKit/DatabaseFramework のセキュリティ機能について説明します。

## 概要

DatabaseKit/DatabaseFramework は2つの独立したセキュリティシステムを提供します：

| システム | 対象 | 制御 | 結果 |
|---------|------|------|------|
| **Field-Level Security** (`@Restricted`) | フィールド単位 | 読み取り/書き込みの可視性 | フィールドのマスキング |
| **Security Rules** (`SecurityPolicy`) | ドキュメント単位 | CRUD 操作の許可/拒否 | 操作のブロック |

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Security Architecture                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Request: GET /employees/123                                                │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │ 1. Security Rules (Document-level)                                   │   │
│   │    SecurityPolicy.allowGet(resource:auth:)                           │   │
│   │    → false: 403 Forbidden (ドキュメント取得不可)                     │   │
│   │    → true: 次のステップへ                                            │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                              ↓                                               │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │ 2. Field-Level Security (Field-level)                                │   │
│   │    FieldSecurityEvaluator.mask(employee, auth:)                      │   │
│   │    → 権限のないフィールドをデフォルト値に置換                        │   │
│   │    → salary: 100000 → 0 (HRロールなし)                               │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                              ↓                                               │
│   Response: { name: "Alice", salary: 0, ssn: "", department: "Engineering" } │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Field-Level Security (`@Restricted`)

### 目的

**特定のフィールドの可視性を制御する**。ドキュメント自体は取得できるが、権限のないフィールドはデフォルト値にマスクされる。

### 使用場面

- 給与情報を HR 部門のみに公開
- 社会保障番号を特定のロールのみに公開
- 個人情報を認証済みユーザーのみに公開
- 管理者専用フィールドの保護

### 定義（database-kit / Core）

```swift
import Core

@Persistable
struct Employee {
    var name: String = ""

    // HR と Manager ロールのみ読み取り可能、HR のみ書き込み可能
    @Restricted(read: .roles(["hr", "manager"]), write: .roles(["hr"]))
    var salary: Double = 0

    // HR ロールのみ読み取り/書き込み可能
    @Restricted(read: .roles(["hr"]), write: .roles(["hr"]))
    var ssn: String = ""

    // 誰でも読み取り可能、Admin のみ書き込み可能
    @Restricted(write: .roles(["admin"]))
    var department: String = ""

    // 認証済みユーザーのみ読み取り可能
    @Restricted(read: .authenticated)
    var internalNotes: String = ""
}
```

### アクセスレベル

```swift
public enum FieldAccessLevel: Sendable, Equatable, Codable {
    /// 誰でもアクセス可能（デフォルト）
    case `public`

    /// 認証済みユーザーのみアクセス可能
    case authenticated

    /// 指定されたロールのみアクセス可能
    case roles(Set<String>)

    /// 所有者のみアクセス可能（ownerID フィールドと比較）
    case owner

    /// 誰もアクセス不可
    case denied
}
```

### 評価（database-framework / DatabaseEngine）

```swift
import DatabaseEngine

// 認証コンテキスト
struct MyAuth: AuthContext {
    let userID: String
    let roles: Set<String>
}

// 従業員データ
var employee = Employee(name: "Alice")
employee.salary = 100000
employee.ssn = "123-45-6789"
employee.department = "Engineering"
employee.internalNotes = "Performance review pending"

// 一般ユーザー（employee ロール）が取得
let regularAuth = MyAuth(userID: "user1", roles: ["employee"])
let masked = FieldSecurityEvaluator.mask(employee, auth: regularAuth)

// 結果:
// masked.name == "Alice"           ← 制限なし、そのまま
// masked.salary == 0               ← マスク（hr/manager ロールなし）
// masked.ssn == ""                 ← マスク（hr ロールなし）
// masked.department == "Engineering" ← 読み取り制限なし
// masked.internalNotes == ""       ← マスク（認証済みだが .authenticated が必要）

// HR ユーザーが取得
let hrAuth = MyAuth(userID: "hr1", roles: ["hr"])
let unmasked = FieldSecurityEvaluator.mask(employee, auth: hrAuth)

// 結果:
// unmasked.salary == 100000        ← 見える（hr ロールあり）
// unmasked.ssn == "123-45-6789"    ← 見える（hr ロールあり）
```

### 書き込み検証

```swift
// 一般ユーザーが給与を変更しようとする
var updated = employee
updated.salary = 150000

do {
    try FieldSecurityEvaluator.validateWrite(
        original: employee,
        updated: updated,
        auth: regularAuth
    )
} catch {
    // FieldSecurityError.writeNotAllowed(type: "Employee", fields: ["salary"])
    print("Error: Cannot modify salary field")
}
```

### 実装の仕組み

`@Persistable` マクロが `@Restricted` 属性を検出し、静的メタデータを生成します：

```swift
// マクロが生成するコード
extension Employee {
    public static var restrictedFieldsMetadata: [RestrictedFieldMetadata] {
        [
            RestrictedFieldMetadata(
                fieldName: "salary",
                readAccess: FieldAccessLevel.roles(["hr", "manager"]),
                writeAccess: FieldAccessLevel.roles(["hr"])
            ),
            RestrictedFieldMetadata(
                fieldName: "ssn",
                readAccess: FieldAccessLevel.roles(["hr"]),
                writeAccess: FieldAccessLevel.roles(["hr"])
            ),
            // ...
        ]
    }

    public func masked(auth: (any AuthContext)?) -> Self {
        var copy = self
        if !FieldAccessLevel.roles(["hr", "manager"]).evaluate(auth: auth) {
            copy.salary = 0  // デフォルト値に置換
        }
        if !FieldAccessLevel.roles(["hr"]).evaluate(auth: auth) {
            copy.ssn = ""
        }
        // ...
        return copy
    }
}
```

**重要**: 静的メタデータにより、`Codable` の encode/decode 後もアクセスレベル情報が保持されます。

---

## Security Rules (`SecurityPolicy`)

### 目的

**ドキュメント全体への CRUD 操作を制御する**。操作が許可されない場合、エラーがスローされドキュメントへのアクセス自体がブロックされる。

### 使用場面

- 認証必須のリソース保護
- 所有者のみ編集可能
- 公開/非公開の切り替え
- ロールベースのアクセス制御
- クエリ制限（limit、offset）

### 定義（database-kit / Core）

```swift
import Core

@Persistable
struct Post {
    var id: String = ULID().ulidString
    var authorID: String = ""
    var title: String = ""
    var content: String = ""
    var isPublic: Bool = false

    #Directory<Post>("posts")
}

extension Post: SecurityPolicy {

    /// 単一ドキュメント取得の許可
    static func allowGet(resource: Post, auth: (any AuthContext)?) -> Bool {
        // 公開記事は誰でも読める、非公開は作者のみ
        resource.isPublic || resource.authorID == auth?.userID
    }

    /// リスト取得の許可
    static func allowList(query: SecurityQuery<Post>, auth: (any AuthContext)?) -> Bool {
        // 認証済みユーザーのみ、100件まで
        auth != nil && (query.limit ?? 0) <= 100
    }

    /// ドキュメント作成の許可
    static func allowCreate(newResource: Post, auth: (any AuthContext)?) -> Bool {
        // 認証済み、かつ authorID が自分
        auth != nil && newResource.authorID == auth?.userID
    }

    /// ドキュメント更新の許可
    static func allowUpdate(resource: Post, newResource: Post, auth: (any AuthContext)?) -> Bool {
        // 作者のみ更新可能、authorID 変更不可
        resource.authorID == auth?.userID
            && newResource.authorID == resource.authorID
    }

    /// ドキュメント削除の許可
    static func allowDelete(resource: Post, auth: (any AuthContext)?) -> Bool {
        // 作者のみ削除可能
        resource.authorID == auth?.userID
    }
}
```

### デフォルト動作

`SecurityPolicy` のデフォルト実装は**全拒否**（Secure by Default）：

```swift
public extension SecurityPolicy {
    static func allowGet(resource: Self, auth: (any AuthContext)?) -> Bool { false }
    static func allowList(query: SecurityQuery<Self>, auth: (any AuthContext)?) -> Bool { false }
    static func allowCreate(newResource: Self, auth: (any AuthContext)?) -> Bool { false }
    static func allowUpdate(resource: Self, newResource: Self, auth: (any AuthContext)?) -> Bool { false }
    static func allowDelete(resource: Self, auth: (any AuthContext)?) -> Bool { false }
}
```

### 使用例（database-framework / DatabaseEngine）

```swift
import DatabaseEngine

struct MyAuth: AuthContext {
    let userID: String
    let roles: Set<String>
}

// 認証情報を TaskLocal に設定
let userAuth = MyAuth(userID: "user123", roles: ["user"])

try await AuthContextKey.$current.withValue(userAuth) {
    let context = container.newContext()

    // 許可される操作
    var post = Post(title: "Hello", content: "World")
    post.authorID = userAuth.userID
    post.isPublic = true
    context.insert(post)
    try await context.save()  // OK: allowCreate が true を返す

    // 拒否される操作
    var anotherPost = Post(title: "Hack", content: "...")
    anotherPost.authorID = "someone-else"  // 他人の ID
    context.insert(anotherPost)
    try await context.save()  // Error: SecurityError がスロー
}
```

### Admin ロールのバイパス

`SecurityConfiguration` で Admin ロールを設定すると、評価がスキップされます：

```swift
let config = SecurityConfiguration(
    isEnabled: true,
    adminRoles: ["admin", "superuser"]
)

let container = try await FDBContainer(
    database: database,
    schema: schema,
    securityDelegate: DefaultSecurityDelegate(configuration: config)
)

// Admin ユーザーは SecurityPolicy の評価をスキップ
let adminAuth = MyAuth(userID: "admin1", roles: ["admin"])
try await AuthContextKey.$current.withValue(adminAuth) {
    // 全ての操作が許可される
}
```

---

## 比較表

| 特性 | @Restricted (Field-Level) | SecurityPolicy (Document-Level) |
|------|--------------------------|--------------------------------|
| **対象** | フィールド | ドキュメント全体 |
| **質問** | 「このフィールドを見せてよいか？」 | 「この操作を許可してよいか？」 |
| **結果** | フィールドをデフォルト値にマスク | 操作を拒否（エラー） |
| **定義場所** | `@Persistable` 型のフィールド属性 | `SecurityPolicy` プロトコル実装 |
| **評価タイミング** | データ返却前 | 操作実行前 |
| **エラー** | なし（マスクのみ） | `SecurityError` がスロー |
| **バイパス** | なし | Admin ロール |

---

## 組み合わせパターン

### パターン 1: Document + Field Security

```swift
@Persistable
struct Employee {
    var id: String = ULID().ulidString
    var managerID: String = ""
    var name: String = ""

    @Restricted(read: .roles(["hr", "manager"]), write: .roles(["hr"]))
    var salary: Double = 0

    @Restricted(read: .roles(["hr"]), write: .roles(["hr"]))
    var ssn: String = ""
}

extension Employee: SecurityPolicy {
    // HR、本人、または上司のみ取得可能
    static func allowGet(resource: Employee, auth: (any AuthContext)?) -> Bool {
        guard let auth = auth else { return false }
        return auth.roles.contains("hr")
            || auth.userID == resource.id
            || auth.userID == resource.managerID
    }

    // 認証済みユーザーのみリスト取得可能
    static func allowList(query: SecurityQuery<Employee>, auth: (any AuthContext)?) -> Bool {
        auth != nil
    }

    // HR のみ作成可能
    static func allowCreate(newResource: Employee, auth: (any AuthContext)?) -> Bool {
        auth?.roles.contains("hr") ?? false
    }

    // HR のみ更新可能
    static func allowUpdate(resource: Employee, newResource: Employee, auth: (any AuthContext)?) -> Bool {
        auth?.roles.contains("hr") ?? false
    }

    // HR のみ削除可能
    static func allowDelete(resource: Employee, auth: (any AuthContext)?) -> Bool {
        auth?.roles.contains("hr") ?? false
    }
}
```

**結果**:

| ユーザー | allowGet | salary 表示 | ssn 表示 |
|---------|----------|------------|----------|
| 未認証 | false (403) | - | - |
| 一般従業員 | false (403) | - | - |
| 本人 | true | マスク (0) | マスク ("") |
| 上司 | true | マスク (0) | マスク ("") |
| Manager ロール | true | 表示 | マスク ("") |
| HR ロール | true | 表示 | 表示 |

### パターン 2: 公開データ + 機密フィールド

```swift
@Persistable
struct Product {
    var id: String = ULID().ulidString
    var name: String = ""
    var price: Double = 0

    // 内部コストは従業員のみ
    @Restricted(read: .roles(["employee"]))
    var cost: Double = 0

    // 仕入れ先情報は購買部門のみ
    @Restricted(read: .roles(["purchasing"]), write: .roles(["purchasing"]))
    var supplierID: String = ""
}

extension Product: SecurityPolicy {
    // 商品情報は誰でも取得可能
    static func allowGet(resource: Product, auth: (any AuthContext)?) -> Bool {
        true
    }

    static func allowList(query: SecurityQuery<Product>, auth: (any AuthContext)?) -> Bool {
        true
    }

    // 作成・更新・削除は従業員のみ
    static func allowCreate(newResource: Product, auth: (any AuthContext)?) -> Bool {
        auth?.roles.contains("employee") ?? false
    }

    static func allowUpdate(resource: Product, newResource: Product, auth: (any AuthContext)?) -> Bool {
        auth?.roles.contains("employee") ?? false
    }

    static func allowDelete(resource: Product, auth: (any AuthContext)?) -> Bool {
        auth?.roles.contains("employee") ?? false
    }
}
```

---

## テナント分離との関係

セキュリティシステムは **テナント分離（Directory + FDB Partition）** とは独立しています：

| 責務 | 担当 | 説明 |
|------|------|------|
| テナント分離 | `#Directory` + FDB Partition | 物理的なデータ分離 |
| 認証チェック | `SecurityPolicy` | ログイン必須か |
| 所有者チェック | `SecurityPolicy` | 自分のデータか |
| フィールド可視性 | `@Restricted` | 特定フィールドの表示/非表示 |

```swift
@Persistable
struct TenantOrder {
    var id: String = ULID().ulidString
    var tenantID: String = ""
    var customerID: String = ""

    @Restricted(read: .roles(["finance"]), write: .roles(["finance"]))
    var internalCost: Double = 0

    // テナント分離は Directory で設定（物理分離）
    #Directory<TenantOrder>("tenants", Field(\.tenantID), "orders", layer: .partition)
}

extension TenantOrder: SecurityPolicy {
    // テナント分離は Directory で既に実現
    // ここではテナント内のアクセス制御のみ

    static func allowGet(resource: TenantOrder, auth: (any AuthContext)?) -> Bool {
        resource.customerID == auth?.userID
    }
    // ...
}
```

---

## モジュール配置

```
database-kit (クライアント共有可能)
└── Core/
    └── Security/
        ├── FieldSecurity/
        │   ├── Restricted.swift              # @Restricted プロパティラッパー
        │   ├── FieldAccessLevel.swift        # アクセスレベル定義
        │   └── RestrictedFieldMetadata.swift # 静的メタデータ
        └── SecurityRule/
            ├── SecurityPolicy.swift          # SecurityPolicy プロトコル
            ├── SecurityQuery.swift           # クエリ情報
            ├── AuthContext.swift             # 認証コンテキスト
            └── SecurityError.swift           # エラー型

database-framework (サーバー専用)
└── DatabaseEngine/
    └── Security/
        ├── FieldSecurity/
        │   └── FieldSecurityEvaluator.swift  # マスキング評価
        └── SecurityRule/
            ├── SecurityConfiguration.swift    # 設定
            ├── DataStoreSecurityDelegate.swift # デリゲート
            └── AuthContextKey.swift           # TaskLocal
```

---

## ベストプラクティス

### 1. Secure by Default

`SecurityPolicy` を実装しない型はデフォルトで全拒否です。明示的に許可ルールを定義してください。

### 2. 最小権限の原則

```swift
// 良い例: 必要最小限の権限
@Restricted(read: .roles(["hr"]), write: .roles(["hr"]))
var salary: Double = 0

// 悪い例: 過度に広い権限
@Restricted(read: .public, write: .public)
var salary: Double = 0
```

### 3. 適切なレイヤーの選択

- **ドキュメント全体へのアクセス制御** → `SecurityPolicy`
- **特定フィールドの機密性** → `@Restricted`
- **テナント分離** → `#Directory` + FDB Partition

### 4. テスト

```swift
@Test("Field masking works correctly")
func testFieldMasking() {
    var employee = Employee(name: "Alice")
    employee.salary = 100000

    let regularAuth = TestAuth(userID: "user1", roles: ["employee"])
    let masked = FieldSecurityEvaluator.mask(employee, auth: regularAuth)

    #expect(masked.name == "Alice")
    #expect(masked.salary == 0)  // マスクされる

    let hrAuth = TestAuth(userID: "hr1", roles: ["hr"])
    let unmasked = FieldSecurityEvaluator.mask(employee, auth: hrAuth)

    #expect(unmasked.salary == 100000)  // 見える
}

@Test("Security policy blocks unauthorized access")
func testSecurityPolicy() async throws {
    let context = container.newContext()

    var post = Post(title: "Secret")
    post.authorID = "other-user"
    post.isPublic = false
    context.insert(post)
    try await context.save()

    // 他人の非公開投稿は取得不可
    let regularAuth = TestAuth(userID: "user1", roles: [])
    try await AuthContextKey.$current.withValue(regularAuth) {
        let fetched = try await context.fetch(Post.self, id: post.id)
        // SecurityError がスローされる
    }
}
```

---

## 参考資料

- [FoundationDB Authorization](https://apple.github.io/foundationdb/authorization.html)
- [PostgreSQL Row Level Security](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
- [Firebase Security Rules](https://firebase.google.com/docs/rules)
