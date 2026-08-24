import DatabaseKit
import DatabaseKitFoundation
import DatabaseTypes
import Foundation
import Testing

@Persistable
private struct FoundationScalarDocument {
    var id: Foundation.UUID
    var timestamp: Date
    var payload: Data
    var amount: Decimal
    var period: DateComponents
}

@Persistable
private struct FoundationDefaultDocument {
    var id: String
    var timestamp: Date = Date(timeIntervalSince1970: 0)
}

@Persistable
private struct InvalidFoundationDefaultDocument {
    var id: String
    var timestamp: Date = Date(timeIntervalSince1970: .nan)
}

@Suite("Foundation model adaptation")
struct FoundationModelAdaptationTests {
    @Test("Foundation defaults use the persisted scalar conversion")
    func foundationDefaultsUsePersistedScalarConversion() throws {
        let timestamp = try Timestamp(secondsSinceUnixEpoch: 0, nanoseconds: 0)
        let schema = try FoundationDefaultDocument.schemaEntity

        #expect(
            schema.fieldMapByName["timestamp"]?.defaultValue
                == .timestamp(timestamp)
        )
    }

    @Test("Invalid Foundation defaults fail schema construction")
    func invalidFoundationDefaultsFailSchemaConstruction() {
        #expect(
            throws: SchemaEntityError.invalidFieldDefault(
                fieldName: "timestamp"
            )
        ) {
            _ = try InvalidFoundationDefaultDocument.schemaEntity
        }
    }

    @Test("Foundation scalar properties round-trip through canonical field values")
    func scalarPropertiesRoundTrip() throws {
        let identifier = Foundation.UUID(
            uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF"
        )
        let unwrappedIdentifier = try #require(identifier)
        let timestamp = Date(timeIntervalSince1970: 1_784_131_200.123_456_7)
        let payload = Data([0, 1, 2, 3, 255])
        let amount = try #require(Decimal(string: "123456.789"))
        var period = DateComponents()
        period.year = 2
        period.month = 3
        period.day = 4

        let source = FoundationScalarDocument(
            id: unwrappedIdentifier,
            timestamp: timestamp,
            payload: payload,
            amount: amount,
            period: period
        )

        let fields = try PersistableFieldEncoder.encode(source)
        let decoded = try FoundationScalarDocument.decodePersistedFields(fields)

        #expect(decoded.id == source.id)
        #expect(decoded.payload == source.payload)
        #expect(decoded.amount == source.amount)
        // CalendarPeriod uses the SQL interval convention of normalizing years
        // into total months. DateComponents therefore round-trips semantically,
        // not by preserving its original component layout.
        #expect(decoded.period.year == nil)
        #expect(decoded.period.month == 27)
        #expect(decoded.period.day == 4)
        #expect(
            try CalendarPeriod(decoded.period)
                == CalendarPeriod(years: 2, months: 3, days: 4)
        )

        let sourceTimestamp = try Timestamp(source.timestamp)
        let decodedTimestamp = try Timestamp(decoded.timestamp)
        #expect(decodedTimestamp == sourceTimestamp)
        #expect(
            FoundationScalarDocument.persistableIdentifierType == .uuid
        )
        #expect(
            source.persistableIdentifierValue
                == .uuid(DatabaseTypes.UUID(unwrappedIdentifier))
        )
    }

    @Test("Foundation adaptation rejects incompatible canonical values")
    func rejectsIncompatibleCanonicalValues() {
        #expect(throws: PersistableDecodingError.self) {
            _ = try Date.decodeFieldValue(
                .string("2026-07-25"),
                field: "timestamp"
            )
        }
        #expect(throws: PersistableDecodingError.self) {
            _ = try Decimal.decodeFieldValue(
                .float64(1.5),
                field: "amount"
            )
        }
        #expect(throws: PersistableEncodingError.self) {
            var unsupported = DateComponents()
            unsupported.hour = 1
            _ = try unsupported.encodeFieldValue()
        }
    }
}
