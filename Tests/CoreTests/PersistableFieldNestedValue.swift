import DatabaseTypes
import DatabaseValue
import Foundation

struct PersistableFieldNestedValue: Sendable, Codable, Equatable {
    let label: String
    let priority: Int64
}
