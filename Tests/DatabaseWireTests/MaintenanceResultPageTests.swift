import DatabaseTypes
@_spi(DatabaseWireRuntime) @testable import DatabaseWire
import Testing

@Suite("Owner-retaining maintenance results")
struct MaintenanceResultPageTests {
    @Test("index status page retains its frame and materializes on demand")
    func indexStatusPageRetainsFrame() throws {
        let response = MaintenanceExecuteOperation.Response.indexStatus(
            .init(
                indexes: [
                    .init(
                        entity: "Event",
                        index: "startsAt",
                        partitions: try FieldObject([
                            (key: "calendar", value: .string("primary")),
                        ]),
                        state: .ready,
                        indexedEntityCount: 42
                    ),
                ],
                continuation: [1, 2]
            )
        )
        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperations.maintenanceExecute,
            requestID: 111,
            response: response
        )
        let decoded = try DatabaseWireDecoder().decodeResponse(
            DatabaseOperations.maintenanceExecute,
            from: frame,
            matching: 111
        )
        guard case .success(.indexStatus(let page)) = decoded else {
            Issue.record("Expected an index status page")
            return
        }
        try expectSharedBacking(
            child: #require(page.retainedEncodedIndexes),
            owner: frame
        )

        #expect(page.indexCount == 1)
        var iterator = page.makeIndexIterator()
        let nextStatus = try iterator.next()
        let status = try #require(nextStatus)
        #expect(status.entity == "Event")
        #expect(status.index == "startsAt")
        #expect(status.indexedEntityCount == 42)
        #expect(try iterator.next() == nil)
    }

    @Test("invalid index state is rejected before iteration")
    func invalidIndexStateIsRejectedDuringAcceptance() throws {
        let response = MaintenanceExecuteOperation.Response.indexStatus(
            .init(
                indexes: [
                    .init(
                        entity: "Event",
                        index: "startsAt",
                        partitions: FieldObject(),
                        state: .ready,
                        indexedEntityCount: 1,
                        detail: "unique-detail"
                    ),
                ]
            )
        )
        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperations.maintenanceExecute,
            requestID: 112,
            response: response
        )
        var corrupted = Array(frame)
        let marker = Array("unique-detail".utf8)
        let markerIndex = try #require(firstIndex(of: marker, in: corrupted))
        let stateIndex = markerIndex - 14
        #expect(corrupted[stateIndex] == 1)
        corrupted[stateIndex] = 0xFF

        #expect(throws: DatabaseWireError.invalidValueTag(0xFF)) {
            _ = try DatabaseWireDecoder().decodeResponse(
                DatabaseOperations.maintenanceExecute,
                from: ByteString(corrupted),
                matching: 112
            )
        }
    }

    private func expectSharedBacking(
        child: ByteString,
        owner: ByteString
    ) throws {
        let ownerRange = try #require(
            owner.withUnsafeBytes { bytes -> Range<UInt>? in
                guard let baseAddress = bytes.baseAddress else {
                    return nil
                }
                let start = UInt(bitPattern: baseAddress)
                return start..<(start + UInt(bytes.count))
            }
        )
        let childAddress = try #require(
            child.withUnsafeBytes { bytes in
                bytes.baseAddress.map { UInt(bitPattern: $0) }
            }
        )
        #expect(ownerRange.contains(childAddress))
    }

    private func firstIndex(
        of pattern: [UInt8],
        in bytes: [UInt8]
    ) -> Int? {
        guard pattern.count <= bytes.count else {
            return nil
        }
        for index in 0...(bytes.count - pattern.count) {
            if bytes[index..<(index + pattern.count)]
                .elementsEqual(pattern) {
                return index
            }
        }
        return nil
    }
}
