import DatabaseTypes
import DatabaseKit
import Testing

@Suite("Unsigned index scalar metadata")
struct IndexUnsignedScalarValueTests {
    @Test("Every fixed-width unsigned integer has a distinct stable scalar identity")
    func unsignedScalarIdentities() {
        #expect(scalarType(of: UInt8.self) == .uint8)
        #expect(scalarType(of: UInt16.self) == .uint16)
        #expect(scalarType(of: UInt32.self) == .uint32)
        #expect(scalarType(of: UInt64.self) == .uint64)

        #expect(IndexScalarType(rawValue: "uint") == nil)
        #expect(IndexScalarType(rawValue: "uint8") == .uint8)
        #expect(IndexScalarType(rawValue: "uint16") == .uint16)
        #expect(IndexScalarType(rawValue: "uint32") == .uint32)
        #expect(IndexScalarType(rawValue: "uint64") == .uint64)
    }

    @Test("Unsigned scalar identities are numeric and non-floating")
    func unsignedScalarTraits() {
        let types: [IndexScalarType] = [
            .uint8,
            .uint16,
            .uint32,
            .uint64,
        ]

        for type in types {
            #expect(type.isNumeric)
            #expect(!type.isFloatingPoint)
        }
    }

    private func scalarType<Value: IndexNumericValue>(
        of type: Value.Type
    ) -> IndexScalarType {
        Value.indexScalarType
    }
}
