import DatabaseTypes
import DatabaseKit

@Persistable
struct PersistableFieldEncoderTestDocument {
    var id: String = "fixture-id"
    var title: String
    var externalID: DatabaseTypes.UUID
    var occurredAt: Timestamp
    var note: String? = nil
    var values: [UInt32]
}
