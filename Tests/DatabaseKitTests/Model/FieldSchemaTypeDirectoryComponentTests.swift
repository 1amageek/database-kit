import Testing
@testable import DatabaseKit

/// Pins the exact set of field kinds a dynamic Directory component admits.
///
/// The expected values are written here rather than derived from
/// `hasCanonicalDirectoryComponent`, so widening or narrowing the property
/// fails this suite instead of silently redefining the declaration contract.
/// The DatabaseFramework Directory bridge owns the matching textual forms and
/// verifies the same set against `DirectoryComponentCodec`.
@Suite("Field Schema Type Directory Component Tests")
struct FieldSchemaTypeDirectoryComponentTests {

    /// `FieldSchemaType` is not `CaseIterable`, so every case is listed here
    /// and the count is asserted rather than derived.
    private static let admission: [(FieldSchemaType, Bool)] = [
        (.bool, true),
        (.int8, true),
        (.int16, true),
        (.int32, true),
        (.int64, true),
        (.uint8, true),
        (.uint16, true),
        (.uint32, true),
        (.uint64, true),
        (.float32, true),
        (.float64, true),
        (.decimal, true),
        (.string, true),
        (.bytes, true),
        (.date, true),
        (.time, true),
        (.dateTime, true),
        (.timestamp, true),
        (.timeSpan, true),
        (.calendarPeriod, true),
        (.geographicPoint, true),
        (.geographicPosition, true),
        (.uuid, true),
        (.enum, true),
        (.vector, false),
        (.object, false),
        (.rdfTerm, false),
        (.reference, false),
        (.nested, false),
    ]

    @Test("Every field kind is classified exactly once")
    func everyFieldKindIsClassifiedExactlyOnce() {
        #expect(Self.admission.count == 29)
        let kinds = Set(Self.admission.map(\.0))
        #expect(kinds.count == Self.admission.count)
    }

    @Test("A field kind admits a dynamic component only where a canonical form exists")
    func admittedKindsMatchTheDeclaredSet() {
        for (kind, expected) in Self.admission {
            #expect(
                kind.hasCanonicalDirectoryComponent == expected,
                "\(kind.rawValue) expected \(expected)"
            )
        }
    }
}
