import DatabaseKit
import Testing

@Suite("RDF term codec limits")
struct RDFTermCodecLimitsTests {
    @Test("Valid limits preserve their exact values")
    func validLimitsPreserveValues() throws {
        let limits = try RDFTermCodecLimits(
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
                RDFTermCodecLimitsError.negativeMaximumBytes(-1)
            ),
            (
                1_024,
                -1,
                256,
                RDFTermCodecLimitsError.negativeMaximumDepth(-1)
            ),
            (
                1_024,
                8,
                0,
                RDFTermCodecLimitsError.nonPositiveMaximumObjectCount(0)
            ),
        ]
    )
    func invalidLimitsFailExplicitly(
        maximumBytes: Int,
        maximumDepth: Int,
        maximumObjectCount: Int,
        expectedError: RDFTermCodecLimitsError
    ) {
        #expect(throws: expectedError) {
            try RDFTermCodecLimits(
                maximumBytes: maximumBytes,
                maximumDepth: maximumDepth,
                maximumObjectCount: maximumObjectCount
            )
        }
    }
}
