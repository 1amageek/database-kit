import DatabaseTypes
import DatabaseValue

extension DatabaseWireWriter {
    public mutating func writeOptionalString(_ value: String?) throws(DatabaseWireError) {
        guard let value else {
            writeBool(false)
            return
        }
        writeBool(true)
        try writeString(value)
    }

    public mutating func writeOptionalBytes(_ value: ByteString?) throws(DatabaseWireError) {
        guard let value else {
            writeBool(false)
            return
        }
        writeBool(true)
        try writeBytes(value)
    }
}
