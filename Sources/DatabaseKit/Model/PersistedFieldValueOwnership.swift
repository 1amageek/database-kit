import DatabaseTypes

/// Materializes primitive payload views at the application-model ownership
/// boundary while preserving canonical value identity.
package enum PersistedFieldValueOwnership {
    package static func detached(_ value: FieldValue) -> FieldValue {
        switch value {
        case .bytes(let bytes):
            return .bytes(bytes.detached())
        case .vector(let vector):
            return .vector(vector.detached())
        case .array(let values):
            return .array(values.map(detached))
        case .object(let object):
            return .object(detached(object))
        case .reference(let reference):
            return .reference(detached(reference))
        case .null,
             .bool,
             .int8,
             .int16,
             .int32,
             .int64,
             .uint8,
             .uint16,
             .uint32,
             .uint64,
             .float32,
             .float64,
             .decimal,
             .string,
             .date,
             .time,
             .dateTime,
             .timestamp,
             .timeSpan,
             .calendarPeriod,
             .geographicPoint,
             .geographicPosition,
             .uuid,
             .rdfTerm:
            return value
        }
    }

    package static func detached(_ object: FieldObject) -> FieldObject {
        let fields = object.fields.map { entry in
            (key: entry.key, value: detached(entry.value))
        }
        do {
            return try FieldObject(fields)
        } catch {
            preconditionFailure(
                "A canonical field object became invalid while detaching"
            )
        }
    }

    package static func detached(
        _ identifier: ReferenceIdentifier
    ) -> ReferenceIdentifier {
        switch identifier {
        case .bytes(let bytes):
            return .bytes(bytes.detached())
        case .composite(let components):
            return .composite(components.map(detached))
        case .bool,
             .int8,
             .int16,
             .int32,
             .int64,
             .uint8,
             .uint16,
             .uint32,
             .uint64,
             .string,
             .uuid:
            return identifier
        }
    }

    package static func detached(
        _ reference: EntityReference
    ) -> EntityReference {
        do {
            return try EntityReference(
                entity: reference.entity,
                id: detached(reference.id),
                partitions: detached(reference.partitions)
            )
        } catch {
            preconditionFailure(
                "A canonical entity reference became invalid while detaching"
            )
        }
    }
}
