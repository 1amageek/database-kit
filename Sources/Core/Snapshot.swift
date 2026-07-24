import DatabaseTypes
/// A point-in-time persisted model plus relationships loaded at the same read version.
@dynamicMemberLookup
public struct Snapshot<T: Persistable>: Sendable {
    public let item: T
    public var relations: [String: any Sendable]

    public init(
        item: T,
        relations: [String: any Sendable] = [:]
    ) {
        self.item = item
        self.relations = relations
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<T, Value>) -> Value {
        item[keyPath: keyPath]
    }

    public func ref<Related: Persistable>(
        _ keyPath: KeyPath<T, DatabaseReference<Related>?>
    ) -> Related? {
        relations[T.fieldName(for: keyPath)] as? Related
    }

    public func ref<Related: Persistable>(
        _ keyPath: KeyPath<T, DatabaseReference<Related>>
    ) -> Related? {
        relations[T.fieldName(for: keyPath)] as? Related
    }

    public func refs<Related: Persistable>(
        _ keyPath: KeyPath<T, [DatabaseReference<Related>]>
    ) -> [Related] {
        relations[T.fieldName(for: keyPath)] as? [Related] ?? []
    }

    public func with<Related: Persistable>(
        _ keyPath: KeyPath<T, DatabaseReference<Related>?>,
        loadedAs value: Related?
    ) -> Snapshot<T> {
        replacingRelation(
            named: T.fieldName(for: keyPath),
            with: value
        )
    }

    public func with<Related: Persistable>(
        _ keyPath: KeyPath<T, DatabaseReference<Related>>,
        loadedAs value: Related?
    ) -> Snapshot<T> {
        replacingRelation(
            named: T.fieldName(for: keyPath),
            with: value
        )
    }

    public func with<Related: Persistable>(
        _ keyPath: KeyPath<T, [DatabaseReference<Related>]>,
        loadedAs value: [Related]
    ) -> Snapshot<T> {
        var updated = relations
        updated[T.fieldName(for: keyPath)] = value
        return Snapshot(item: item, relations: updated)
    }

    private func replacingRelation<Related: Persistable>(
        named fieldName: String,
        with value: Related?
    ) -> Snapshot<T> {
        var updated = relations
        if let value {
            updated[fieldName] = value
        } else {
            updated.removeValue(forKey: fieldName)
        }
        return Snapshot(item: item, relations: updated)
    }
}

extension Snapshot: Equatable where T: Equatable {
    public static func == (lhs: Snapshot<T>, rhs: Snapshot<T>) -> Bool {
        lhs.item == rhs.item
    }
}

extension Snapshot: Hashable where T: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(item)
    }
}

extension Snapshot: Identifiable where T: Identifiable {
    public var id: T.ID {
        item.id
    }
}

extension Snapshot: CustomStringConvertible {
    public var description: String {
        let relationSummary = relations.isEmpty
            ? ""
            : ", \(relations.count) relation(s) loaded"
        return "Snapshot<\(T.persistableType)>(\(item.id)\(relationSummary))"
    }
}

extension Snapshot: CustomDebugStringConvertible {
    public var debugDescription: String {
        var lines = ["Snapshot<\(T.persistableType)>", "  item: \(item)"]
        if !relations.isEmpty {
            lines.append("  relations:")
            for (name, value) in relations {
                lines.append("    \(name): \(value)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
