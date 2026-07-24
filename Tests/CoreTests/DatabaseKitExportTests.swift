import DatabaseKit
import Testing

@Suite("DatabaseKit exports")
struct DatabaseKitExportTests {
    @Test("Convenience module exposes relationship declarations")
    func exportsRelationshipDeclarations() {
        let descriptor = RelationshipDescriptor(
            ownerTypeName: "Order",
            propertyName: "customer",
            propertyFieldNumber: 1,
            relatedTypeName: "Customer",
            cardinality: .requiredToOne,
            deleteRule: .deny
        )

        #expect(descriptor.name == "Order.customer")
        #expect(descriptor.isToOne)
    }
}
