import DatabaseTypes
@_spi(DatabaseWireRuntime) @testable import DatabaseWire
import Testing

@Suite("DatabaseWire nesting state")
struct DatabaseWireNestingStateTests {
    @Test("reader reports an unbalanced close without trapping")
    func readerRejectsUnbalancedClose() {
        var reader = DatabaseWireReader(ByteString())

        #expect(throws: DatabaseWireError.invalidNestingState) {
            try reader.endNestedValue()
        }
    }

    @Test("writer reports an unbalanced close without trapping")
    func writerRejectsUnbalancedClose() {
        #expect(throws: DatabaseWireError.invalidNestingState) {
            _ = try DatabaseWireWriter.encode {
                (writer: inout DatabaseWireWriter)
                    throws(DatabaseWireError) in
                try writer.endNestedValue()
            }
        }
    }

    @Test("reader restores its enclosing depth after a nested failure")
    func readerRestoresDepthAfterFailure() {
        var reader = DatabaseWireReader(ByteString())

        #expect(throws: DatabaseWireError.truncated) {
            _ = try reader.withNestedValue {
                (reader: inout DatabaseWireReader)
                    throws(DatabaseWireError) in
                try reader.endNestedValue()
                throw DatabaseWireError.truncated
            }
        }
        #expect(reader.currentNestingDepth == 0)
        #expect(throws: DatabaseWireError.invalidNestingState) {
            try reader.endNestedValue()
        }
    }

    @Test("writer restores its enclosing depth after a nested failure")
    func writerRestoresDepthAfterFailure() {
        #expect(throws: DatabaseWireError.truncated) {
            _ = try DatabaseWireWriter.encode {
                (writer: inout DatabaseWireWriter)
                    throws(DatabaseWireError) in
                try writer.withNestedValue {
                    (writer: inout DatabaseWireWriter)
                        throws(DatabaseWireError) in
                    try writer.endNestedValue()
                    throw DatabaseWireError.truncated
                }
            }
        }
    }
}
