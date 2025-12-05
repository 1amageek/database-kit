// RelationshipMacro.swift
// Relationship - @Relationship macro declaration
//
// Reference: SwiftData @Relationship macro

// MARK: - @Relationship Macro Declaration

/// Declares a relationship between Persistable types
///
/// The `@Relationship` macro marks a FK field as a relationship to another
/// Persistable type. It enables:
/// - Automatic relationship index generation
/// - Delete rule enforcement
/// - Snapshot property generation for easy access
///
/// ## FK Field Naming Convention
///
/// - To-One: `xxxxID` (e.g., `customerID: String?`)
/// - To-Many: `xxxxIDs` (e.g., `orderIDs: [String]`)
///
/// The macro generates Snapshot extensions that provide cleaner access:
/// - `customerID` → `snapshot.customer`
/// - `orderIDs` → `snapshot.orders`
///
/// ## Usage
///
/// ```swift
/// @Persistable
/// struct Order {
///     var total: Double
///
///     // To-One: FK to Customer
///     @Relationship(Customer.self, deleteRule: .nullify)
///     var customerID: String?
/// }
///
/// @Persistable
/// struct Customer {
///     var name: String
///
///     // To-Many: array of FK to Order
///     @Relationship(Order.self, deleteRule: .cascade)
///     var orderIDs: [String] = []
/// }
///
/// @Persistable
/// struct Employee {
///     var name: String
///
///     // Self-referencing relationship
///     @Relationship(Employee.self, deleteRule: .nullify)
///     var managerID: String?
/// }
/// ```
///
/// ## Querying with Relationships
///
/// ```swift
/// // Load orders with customer data
/// let orders = try await context.fetch(Order.self)
///     .joining(\.customerID)
///     .execute()
///
/// for order in orders {
///     print(order.customer?.name)  // Direct access via generated property
/// }
/// ```
///
/// ## Delete Rules
///
/// - `.nullify` (default): Set referencing item's FK to nil
/// - `.cascade`: Delete all referencing items
/// - `.deny`: Throw error if referencing items exist
/// - `.noAction`: Do nothing (may leave orphans)
///
/// - Parameters:
///   - type: The related Persistable type (e.g., `Customer.self`)
///   - deleteRule: Action to take when the related model is deleted (default: `.nullify`)
@attached(peer)
public macro Relationship<T>(
    _ type: T.Type,
    deleteRule: DeleteRule = .nullify
) = #externalMacro(module: "RelationshipMacros", type: "RelationshipMacro")
