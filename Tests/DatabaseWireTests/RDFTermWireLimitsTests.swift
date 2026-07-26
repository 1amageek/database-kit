import DatabaseKit
@testable import DatabaseWire
import Testing

@Suite("RDF term wire limits")
struct RDFTermWireLimitsTests {
    @Test("Valid limits preserve their exact values")
    func validLimitsPreserveValues() throws {
        let limits = try RDFTermWireLimits(
            maximumBytes: 1_024,
            maximumDepth: 8,
            maximumObjectCount: 256
        )

        #expect(limits.maximumBytes == 1_024)
        #expect(limits.maximumDepth == 8)
        #expect(limits.maximumObjectCount == 256)
    }

    @Test(
        "Invalid limits fail explicitly",
        arguments: [
            (
                -1,
                8,
                256,
                RDFTermWireLimitsError.negativeMaximumBytes(-1)
            ),
            (
                1_024,
                -1,
                256,
                RDFTermWireLimitsError.negativeMaximumDepth(-1)
            ),
            (
                1_024,
                8,
                0,
                RDFTermWireLimitsError.nonPositiveMaximumObjectCount(0)
            ),
        ]
    )
    func invalidLimitsFailExplicitly(
        maximumBytes: Int,
        maximumDepth: Int,
        maximumObjectCount: Int,
        expectedError: RDFTermWireLimitsError
    ) {
        #expect(throws: expectedError) {
            try RDFTermWireLimits(
                maximumBytes: maximumBytes,
                maximumDepth: maximumDepth,
                maximumObjectCount: maximumObjectCount
            )
        }
    }
}
