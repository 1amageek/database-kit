import DatabaseKit
import Testing

@Suite("Command identifier")
struct CommandIdentifierTests {
    @Test("canonical identifiers preserve their semantic name")
    func canonicalIdentifier() throws {
        let identifier = try CommandIdentifier("calendar.activateImport2")

        #expect(identifier.rawValue == "calendar.activateImport2")
    }

    @Test(
        "invalid identifiers fail deterministically",
        arguments: [
            ("", CommandIdentifierError.empty),
            (".calendar", .adjacentSeparator),
            ("calendar..activate", .adjacentSeparator),
            ("calendar.", .trailingSeparator),
            ("calendar.activate-import", .invalidByte(0x2D)),
            ("calendar.1activate", .invalidStart(0x31)),
        ]
    )
    func invalidIdentifier(
        rawValue: String,
        expectedError: CommandIdentifierError
    ) {
        #expect(throws: expectedError) {
            try CommandIdentifier(rawValue)
        }
    }

    @Test("identifier ordering follows canonical UTF-8 ordering")
    func canonicalOrdering() throws {
        let activate = try CommandIdentifier("calendar.activate")
        let inspect = try CommandIdentifier("calendar.inspect")

        #expect(activate < inspect)
    }
}
