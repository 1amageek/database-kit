import DatabaseTypes
import Testing
import Foundation
@testable import DatabaseKit

@Suite("EnumMetadata Tests")
struct EnumMetadataTests {

    @Test("EnumMetadata initialization")
    func testInit() {
        let metadata = EnumMetadata(
            typeName: "Status",
            cases: ["active", "inactive", "pending"]
        )

        #expect(metadata.typeName == "Status")
        #expect(metadata.cases == ["active", "inactive", "pending"])
    }

    @Test("EnumMetadata isValidCase - valid cases")
    func testIsValidCaseValid() {
        let metadata = EnumMetadata(
            typeName: "Status",
            cases: ["active", "inactive", "pending"]
        )

        #expect(metadata.isValidCase("active") == true)
        #expect(metadata.isValidCase("inactive") == true)
        #expect(metadata.isValidCase("pending") == true)
    }

    @Test("EnumMetadata isValidCase - invalid cases")
    func testIsValidCaseInvalid() {
        let metadata = EnumMetadata(
            typeName: "Status",
            cases: ["active", "inactive", "pending"]
        )

        #expect(metadata.isValidCase("unknown") == false)
        #expect(metadata.isValidCase("") == false)
        #expect(metadata.isValidCase("ACTIVE") == false)  // Case sensitive
    }

    @Test("EnumMetadata Equatable conformance")
    func testEquatable() {
        let metadata1 = EnumMetadata(
            typeName: "Status",
            cases: ["active", "inactive"]
        )

        let metadata2 = EnumMetadata(
            typeName: "Status",
            cases: ["active", "inactive"]
        )

        let metadata3 = EnumMetadata(
            typeName: "Status",
            cases: ["active", "pending"]  // Different cases
        )

        #expect(metadata1 == metadata2)
        #expect(metadata1 != metadata3)
    }

    @Test("EnumMetadata Sendable conformance")
    func testSendable() {
        let metadata = EnumMetadata(
            typeName: "Status",
            cases: ["active", "inactive"]
        )

        Task {
            let _ = metadata  // Can be captured in async context
        }

        #expect(metadata.typeName == "Status")
    }

    @Test("@Persistable Int enum uses canonical metadata and field value")
    func persistableIntEnum() {
        #expect(
            PersistableIntStatus.fieldEnumMetadata(named: "PersistableIntStatus")
                == EnumMetadata(
                    typeName: "PersistableIntStatus",
                    cases: ["1", "2"]
                )
        )
        #expect(PersistableIntStatus.closed.encodeFieldValue() == .int64(2))
    }
}

@Persistable
private enum PersistableIntStatus: Int {
    case open = 1
    case closed = 2
}
