import DatabaseTypes
import DatabaseKit
import Foundation

@Persistable
struct PersistableFieldEncoderTestDocument {
    var title: String
    var externalID: Foundation.UUID
    var occurredAt: Date
    var note: String? = nil
    var values: [UInt32]
}
