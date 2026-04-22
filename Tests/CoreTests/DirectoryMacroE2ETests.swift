import Testing
@testable import Core

@Suite("#Directory Macro E2E Tests")
struct DirectoryMacroE2ETests {

    @Test("#Directory static path participates in schema construction")
    func staticDirectoryParticipatesInSchemaConstruction() throws {
        #expect(StaticDirectoryRecord.directoryLayer == .default)
        #expect(StaticDirectoryRecord.hasDynamicDirectory == false)
        #expect(StaticDirectoryRecord.directoryFieldNames.isEmpty)

        let components = StaticDirectoryRecord.directoryPathComponents
        #expect(components.count == 2)
        #expect((components[0] as? Path)?.value == "macro-e2e")
        #expect((components[1] as? Path)?.value == "static-records")

        let schema = Schema([StaticDirectoryRecord.self])
        let entity = try #require(schema.entity(for: StaticDirectoryRecord.self))
        #expect(entity.directoryComponents == [
            .staticPath("macro-e2e"),
            .staticPath("static-records")
        ])
        #expect(entity.hasDynamicDirectory == false)
        #expect(try entity.resolvedDirectoryPath() == [
            "macro-e2e",
            "static-records"
        ])
    }

    @Test("#Directory dynamic Field path participates in schema construction")
    func dynamicDirectoryParticipatesInSchemaConstruction() throws {
        #expect(PartitionedDirectoryRecord.directoryLayer == .partition)
        #expect(PartitionedDirectoryRecord.hasDynamicDirectory == true)
        #expect(PartitionedDirectoryRecord.directoryFieldNames == ["tenantID"])

        let components = PartitionedDirectoryRecord.directoryPathComponents
        #expect(components.count == 3)
        #expect((components[0] as? Path)?.value == "tenants")
        #expect((components[2] as? Path)?.value == "partitioned-records")

        let dynamicComponent = try #require(components[1] as? Field<PartitionedDirectoryRecord>)
        #expect(dynamicComponent.value == \PartitionedDirectoryRecord.tenantID)
        #expect(PartitionedDirectoryRecord.fieldName(for: dynamicComponent.value) == "tenantID")

        let schema = Schema([PartitionedDirectoryRecord.self])
        let entity = try #require(schema.entity(for: PartitionedDirectoryRecord.self))
        #expect(entity.directoryComponents == [
            .staticPath("tenants"),
            .dynamicField(fieldName: "tenantID"),
            .staticPath("partitioned-records")
        ])
        #expect(entity.hasDynamicDirectory == true)
        #expect(entity.dynamicFieldNames == ["tenantID"])
        #expect(try entity.resolvedDirectoryPath(partitionValues: ["tenantID": "acme"]) == [
            "tenants",
            "acme",
            "partitioned-records"
        ])
        #expect(throws: DirectoryPathError.self) {
            try entity.resolvedDirectoryPath()
        }
    }
}

@Persistable
private struct StaticDirectoryRecord {
    #Directory<StaticDirectoryRecord>("macro-e2e", "static-records")

    var title: String
}

@Persistable
private struct PartitionedDirectoryRecord {
    #Directory<PartitionedDirectoryRecord>(
        "tenants",
        Field<PartitionedDirectoryRecord>(\.tenantID),
        "partitioned-records",
        layer: .partition
    )

    var tenantID: String
    var title: String
}
