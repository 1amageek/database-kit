/// A model-scoped field selected by an index declaration.
///
/// The generic model is a compile-time constraint. Runtime storage contains
/// only stable field identity and key ordering.
public struct IndexField<Model: Persistable>: Sendable, Hashable {
    public let metadata: IndexFieldMetadata

    public init<Value>(
        _ field: Field<Model, Value>,
        order: IndexFieldOrder = .ascending
    ) {
        self.metadata = IndexFieldMetadata(
            identity: field.identity,
            order: order
        )
    }

    package init(metadata: IndexFieldMetadata) {
        self.metadata = metadata
    }

    public var identity: FieldIdentity {
        metadata.identity
    }

    public var order: IndexFieldOrder {
        metadata.order
    }

    public var name: String {
        metadata.name
    }
}

extension Field where Root: Persistable {
    public var ascending: IndexField<Root> {
        IndexField(self, order: .ascending)
    }

    public var descending: IndexField<Root> {
        IndexField(self, order: .descending)
    }
}
