/// One ordered field in an index key.
public struct IndexKey<FieldReference> {
    public let field: FieldReference
    public let order: IndexFieldOrder

    public init(
        _ field: FieldReference,
        order: IndexFieldOrder = .ascending
    ) {
        self.field = field
        self.order = order
    }

    public static func ascending(_ field: FieldReference) -> Self {
        Self(field, order: .ascending)
    }

    public static func descending(_ field: FieldReference) -> Self {
        Self(field, order: .descending)
    }

    public func map<NewFieldReference, Failure: Error>(
        _ transform: (FieldReference) throws(Failure) -> NewFieldReference
    ) throws(Failure) -> IndexKey<NewFieldReference> {
        IndexKey<NewFieldReference>(try transform(field), order: order)
    }
}

extension IndexKey: Sendable where FieldReference: Sendable {}
extension IndexKey: Equatable where FieldReference: Equatable {}
extension IndexKey: Hashable where FieldReference: Hashable {}
