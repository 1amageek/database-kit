import DatabaseTypes
import DatabaseKit
import Synchronization
import Testing

@Suite("Flat composite query values", .timeLimit(.minutes(1)))
struct QueryCompositeValueTests {
    private var limits: QueryValueLimits {
        QueryValueLimits(maximumRetainedBytes: 20_000_000, maximumTotalNodes: 100_000,
                         maximumNestingDepth: 1024, maximumCollectionElements: 100_000)
    }

    private func descriptor(_ types: [QueryColumnType], nullable: Bool = true) throws -> QueryCompositeType {
        try QueryCompositeType(columns: types.enumerated().map {
            try QueryColumn(number: UInt32($0.offset + 1), name: "field", type: $0.element, isNullable: nullable)
        }, limits: limits)
    }

    @Test func orderedDescriptorsPreserveExactNamesAndTypes() throws {
        let columns = [
            try QueryColumn(number: 1, name: "e\u{301}", type: .sql(.integer), isNullable: false),
            try QueryColumn(number: 2, name: "e\u{301}", type: .primitive(.bytes), isNullable: true),
        ]
        let type = try QueryCompositeType(columns: columns, limits: limits)
        #expect(type.columns.elementsEqual(columns))
        let other = try QueryCompositeType(columns: columns, limits: limits)
        #expect(type == other)
        #expect(type.hashValue == other.hashValue)
        let changed = try QueryCompositeType(columns: [
            QueryColumn(number: 1, name: "\u{e9}", type: .sql(.integer), isNullable: false), columns[1],
        ], limits: limits)
        #expect(type != changed)
        #expect(throws: QueryValueError.invalidColumnNumber(2)) {
            try QueryCompositeType(columns: [columns[1]], limits: limits)
        }
    }

    @Test func typedNullAndEmptyCompositeRemainDifferent() throws {
        let type = try QueryCompositeType(columns: [], limits: limits)
        let empty = try QueryCompositeValue(type: type, fields: [], limits: limits)
        #expect(empty.fields.isEmpty)
        #expect(!QueryValue.composite(empty).isNull)
        #expect(QueryValueValidator.accepts(.primitive(.null), type: .sql(.composite(type))))
        try QueryValueValidator.validate(.primitive(.null), type: .sql(.composite(type)), limits: limits)
        let parameter = QueryParameter(position: 1, value: .primitive(.null), type: .sql(.composite(type)))
        #expect(parameter.type == .sql(.composite(type)))
        #expect(QueryValue.composite(empty) != .primitive(.null))
    }

    @Test func compositeArityTypeAndNullabilityFailExplicitly() throws {
        let type = try descriptor([.sql(.integer)], nullable: false)
        #expect(throws: QueryValueError.compositeFieldCountMismatch(expected: 1, actual: 0)) {
            try QueryCompositeValue(type: type, fields: [], limits: limits)
        }
        #expect(throws: QueryValueError.elementTypeMismatch(index: 0)) {
            try QueryCompositeValue(type: type, fields: [.primitive(.string("wrong"))], limits: limits)
        }
        #expect(throws: QueryValueError.nullCompositeField(index: 0)) {
            try QueryCompositeValue(type: type, fields: [.primitive(.null)], limits: limits)
        }
        let nullable = try descriptor([.sql(.integer)])
        let allNull = try QueryCompositeValue(type: nullable, fields: [.primitive(.null)], limits: limits)
        #expect(!QueryValue.composite(allNull).isNull)
        #expect(!QueryValueValidator.accepts(.composite(allNull), type: .sql(.composite(type))))
    }

    @Test func arraysAndCompositeFieldsPreserveBoundsAndSelectedTypes() throws {
        let rowType = try descriptor([.sql(.integer)])
        let row = try QueryCompositeValue(type: rowType, fields: [.primitive(.int32(7))], limits: limits)
        let array = try QueryArrayValue(elementType: .composite(rowType),
            dimensions: [QueryArrayDimension(lowerBound: -7, length: 2)],
            elements: [.composite(row), .primitive(.null)], limits: limits)
        let outerType = try descriptor([.sql(.array(.composite(rowType))), .sql(.composite(rowType))])
        let outer = try QueryCompositeValue(type: outerType, fields: [.array(array), .composite(row)], limits: limits)
        guard case .array(let restored) = outer.fields[0] else { Issue.record("Expected array field"); return }
        #expect(restored.elementType == .composite(rowType))
        #expect(restored.dimensions[0].lowerBound == -7)
        #expect(restored.elements[0] == .composite(row))
        #expect(restored.elements[1].isNull)
        let copied = try QueryCompositeValue(type: outerType, fields: Array(outer.fields), limits: limits)
        #expect(outer == copied)
        #expect(outer.hashValue == copied.hashValue)
        let empty = try QueryArrayValue(elementType: .composite(rowType), dimensions: [], elements: [], limits: limits)
        #expect(empty.dimensions.isEmpty && empty.elements.isEmpty)
    }

    @Test func logicalAndRetainedQuotasHaveExactBoundaries() throws {
        let type = try descriptor([.sql(.integer)])
        let value = QueryValue.composite(try QueryCompositeValue(type: type, fields: [.primitive(.int32(3))], limits: limits))
        let measured = try QueryValueValidator.measure(value)
        #expect(measured.nodeCount == 5)
        #expect(measured.collectionElementCount == 2)
        let exact = QueryValueLimits(maximumRetainedBytes: measured.retainedByteCount,
            maximumTotalNodes: measured.nodeCount, maximumNestingDepth: measured.maximumNestingDepth,
            maximumCollectionElements: measured.collectionElementCount)
        try QueryValueValidator.validate(value, limits: exact)
        for (bytes, nodes, depth, edges) in [
            (measured.retainedByteCount - 1, measured.nodeCount, measured.maximumNestingDepth, measured.collectionElementCount),
            (measured.retainedByteCount, measured.nodeCount - 1, measured.maximumNestingDepth, measured.collectionElementCount),
            (measured.retainedByteCount, measured.nodeCount, measured.maximumNestingDepth - 1, measured.collectionElementCount),
            (measured.retainedByteCount, measured.nodeCount, measured.maximumNestingDepth, measured.collectionElementCount - 1),
        ] {
            #expect(throws: QueryValueError.self) {
                try QueryValueValidator.validate(value, limits: QueryValueLimits(maximumRetainedBytes: bytes,
                    maximumTotalNodes: nodes, maximumNestingDepth: depth, maximumCollectionElements: edges))
            }
        }
        let typeFootprint = try type.measure()
        #expect(typeFootprint.nodeCount == 3)
        #expect(typeFootprint.maximumNestingDepth == 3)
        #expect(throws: QueryValueError.self) {
            try QueryCompositeType(columns: Array(type.columns), limits: QueryValueLimits(
                maximumRetainedBytes: limits.maximumRetainedBytes, maximumTotalNodes: 2,
                maximumNestingDepth: 3, maximumCollectionElements: 1))
        }
    }

    @Test func plannedCapacityCeilingsAndActualReportsAreIndependent() throws {
        var builder = try QueryValueBuilder(limits: limits, nodeCapacity: 2, childIndexCapacity: 1,
            dimensionCapacity: 1, typeNodeCapacity: 1, columnCapacity: 0)
        let scalar = try builder.append(.primitive(.int32(1)))
        let root = try builder.appendArray(elementType: .integer,
            dimensions: [QueryArrayDimension(lowerBound: 4, length: 1)], elements: [scalar])
        let construction = builder.constructionRetainedByteCount
        guard case .array(let array) = try builder.finish(root: root) else { Issue.record("Expected array"); return }
        #expect(array.storageFootprint.nodeCapacity >= 2)
        #expect(array.storageFootprint.childIndexCapacity >= 1)
        #expect(array.storageFootprint.dimensionCapacity >= 1)
        #expect(construction >= array.storageFootprint.retainedStorageByteCount)
        #expect(try QueryValueBuilder.constructionByteCount(nodeCapacity: 2, childIndexCapacity: 1,
            dimensionCapacity: 1, typeNodeCapacity: 1, columnCapacity: 0) > 0)
        #expect(throws: QueryValueError.self) {
            try QueryValueBuilder.constructionByteCount(nodeCapacity: -1, childIndexCapacity: 0,
                dimensionCapacity: 0, typeNodeCapacity: 0, columnCapacity: 0)
        }
        #expect(throws: QueryValueError.arithmeticOverflow) {
            try QueryValueBuilder.constructionByteCount(nodeCapacity: .max, childIndexCapacity: 0,
                dimensionCapacity: 0, typeNodeCapacity: 0, columnCapacity: 0)
        }
    }

    @Test func eachPlannedCeilingRejectsItsFirstExcess() throws {
        let shape = [try QueryArrayDimension(lowerBound: 1, length: 1)]
        for capacities in [(1, 1, 1, 1), (2, 0, 1, 1), (2, 1, 0, 1), (2, 1, 1, 0)] {
            var builder = try QueryValueBuilder(limits: limits, nodeCapacity: capacities.0,
                childIndexCapacity: capacities.1, dimensionCapacity: capacities.2,
                typeNodeCapacity: capacities.3, columnCapacity: 0)
            let scalar = try builder.append(.primitive(.int32(1)))
            #expect(throws: QueryValueError.self) {
                try builder.appendArray(elementType: .integer, dimensions: shape, elements: [scalar])
            }
            #expect(throws: QueryValueError.invalidValueConstruction) { try builder.finish(root: scalar) }
        }
        let type = try descriptor([.sql(.integer)])
        var builder = try QueryValueBuilder(limits: limits, nodeCapacity: 2, childIndexCapacity: 1,
            dimensionCapacity: 0, typeNodeCapacity: 2, columnCapacity: 0)
        let scalar = try builder.append(.primitive(.int32(1)))
        #expect(throws: QueryValueError.resourceLimit(resource: "queryPlannedColumnCapacity", actual: 1, maximum: 0)) {
            try builder.appendComposite(type: type, fields: [scalar])
        }
    }

    @Test func invalidRepeatedAndOrphanReferencesCannotPublish() throws {
        let shape = [try QueryArrayDimension(lowerBound: 1, length: 2)]
        var repeated = QueryValueBuilder(limits: limits)
        let id = try repeated.append(.primitive(.int32(1)))
        #expect(throws: QueryValueError.invalidBuilderReference(index: id)) {
            try repeated.appendArray(elementType: .integer, dimensions: shape, elements: [id, id])
        }
        #expect(throws: QueryValueError.invalidValueConstruction) { try repeated.append(.primitive(.int32(2))) }
        var invalid = QueryValueBuilder(limits: limits)
        #expect(throws: QueryValueError.invalidBuilderReference(index: 99)) {
            try invalid.appendArray(elementType: .integer,
                dimensions: [QueryArrayDimension(lowerBound: 1, length: 1)], elements: [99])
        }
        var orphaned = QueryValueBuilder(limits: limits)
        _ = try orphaned.append(.primitive(.int32(1)))
        let last = try orphaned.append(.primitive(.int32(2)))
        #expect(throws: QueryValueError.invalidValueConstruction) { try orphaned.finish(root: last) }
        let fresh = try QueryCompositeValue(type: descriptor([]), fields: [], limits: limits)
        #expect(fresh.fields.isEmpty)
        let releases = CompositeReleaseCounter()
        do {
            let owner = CompositeReleaseOwner(releases: releases)
            var failed = QueryValueBuilder(limits: limits)
            let child = try failed.append(.primitive(.bytes(ByteString(retaining: owner))))
            let incompatible = try descriptor([.sql(.integer)])
            #expect(throws: QueryValueError.elementTypeMismatch(index: 0)) {
                try failed.appendComposite(type: incompatible, fields: [child])
            }
            #expect(releases.count.withLock { $0 } == 0)
        }
        #expect(releases.count.withLock { $0 } == 1)
    }

    @Test func deepDescriptorValueIdentityAndReleaseUseFlatOwners() throws {
        var types = QueryTypeBuilder(limits: limits)
        var type = try types.append(.sql(.integer))
        for i in 0..<180 {
            if i.isMultiple(of: 2) {
                type = try types.appendComposite(columns: [QueryTypeColumn(number: 1, name: "field", type: type, isNullable: false)])
            } else { type = try types.appendArray(element: type) }
        }
        let rootType = try types.finish(root: type)
        var descriptors: [DataType] = []
        var current = rootType
        while true {
            descriptors.append(current)
            switch current {
            case .array(let child): current = child
            case .composite(let row):
                guard case .sql(let child) = row.columns[0].type else { Issue.record("Expected SQL type"); return }
                current = child
            default: break
            }
            if case .integer = current { break }
        }
        var values = QueryValueBuilder(limits: limits)
        var value = try values.append(.primitive(.int32(9)))
        for descriptor in descriptors.reversed() {
            switch descriptor {
            case .array(let child):
                value = try values.appendArray(elementType: child,
                    dimensions: [QueryArrayDimension(lowerBound: -3, length: 1)], elements: [value])
            case .composite(let row): value = try values.appendComposite(type: row, fields: [value])
            default: Issue.record("Unexpected descriptor"); return
            }
        }
        let root = try values.finish(root: value)
        var copy = QueryValueBuilder(limits: limits)
        let copied = try copy.append(root)
        let other = try copy.finish(root: copied)
        #expect(root == other)
        #expect(root.hashValue == other.hashValue)
        // Ninety composite/array descriptor pairs add 270 levels; the outer value edge adds one.
        let measured = try QueryValueValidator.measure(root)
        #expect(measured.maximumNestingDepth == 272)
    }

    @Test func retainedViewsKeepSiblingOwnersAndColumnsDoNotKeepPayloads() throws {
        let releases = CompositeReleaseCounter()
        var fields: QueryValueElements?
        let columns: QueryCompositeColumns
        do {
            let owner = CompositeReleaseOwner(releases: releases)
            let innerType = try descriptor([.sql(.integer)])
            let inner = try QueryCompositeValue(type: innerType, fields: [.primitive(.int32(5))], limits: limits)
            let type = try descriptor([.sql(.composite(innerType)), .sql(.blob)])
            let root = try QueryCompositeValue(type: type,
                fields: [.composite(inner), .primitive(.bytes(ByteString(retaining: owner)))], limits: limits)
            fields = root.fields; columns = root.type.columns
        }
        #expect(releases.count.withLock { $0 } == 0)
        if let fields {
            guard case .composite(let child) = fields[0] else { Issue.record("Expected retained child"); return }
            #expect(child.fields[0] == .primitive(.int32(5)))
            #expect(child.storageFootprint.leafRetainedByteCount > 0)
            #expect(try QueryValueValidator.measure(.composite(child)).retainedByteCount > child.storageFootprint.leafRetainedByteCount)
        }
        fields = nil
        #expect(releases.count.withLock { $0 } == 1)
        #expect(columns.count == 2)
    }

    @Test func resultOnlyDescriptorsRejectEveryPersistenceEntry() throws {
        let row = try descriptor([.sql(.integer)])
        for type: DataType in [.composite(row), .array(.composite(row))] {
            let declaration = QueryColumnType.sql(type)
            #expect(throws: QueryValueError.invalidPersistenceDescriptor) {
                try QueryFieldStorageAdapter.validateDescriptor(declaration, fieldType: .object, isArray: false)
            }
            #expect(throws: QueryValueError.invalidPersistenceDescriptor) {
                try QueryFieldStorageAdapter.encode(.primitive(.null), type: declaration, limits: limits)
            }
            #expect(throws: QueryValueError.invalidPersistenceDescriptor) {
                try QueryFieldStorageAdapter.decode(.null, type: declaration, limits: limits)
            }
            #expect(throws: QueryValueError.invalidPersistenceDescriptor) {
                try QueryFieldStorageAdapter.measureDecoded(.null, type: declaration)
            }
            #expect(throws: QueryValueError.invalidPersistenceDescriptor) {
                try QueryFieldStorageAdapter.inferredLimits(for: QueryValue.primitive(.null), type: declaration)
            }
            #expect(throws: QueryValueError.invalidPersistenceDescriptor) {
                try QueryFieldStorageAdapter.measure(.primitive(.null), type: declaration)
            }
            #expect(throws: QueryValueError.invalidPersistenceDescriptor) {
                try QueryFieldStorageAdapter.inferredLimits(for: FieldValue.null, type: declaration)
            }
            #expect(throws: SchemaEntityError.invalidQueryField(fieldName: "value", cause: .invalidPersistenceDescriptor)) {
                try Schema.Entity(name: "ResultOnly", identifierType: .string, fields: [
                    FieldSchema(name: "value", fieldNumber: 1, type: .object, isOptional: true,
                                defaultValue: .null, queryType: declaration)])
            }
        }
    }
}

private final class CompositeReleaseOwner: ByteStringOwner {
    let bytes = ByteString(utf8: "payload")
    let releases: CompositeReleaseCounter
    init(releases: CompositeReleaseCounter) { self.releases = releases }
    var count: Int { bytes.count }
    var retainedByteCount: Int? { bytes.retainedByteCount }
    func borrowBytes(_ body: (UnsafeRawBufferPointer) throws -> Void) rethrows {
        try bytes.withUnsafeBytes(body)
    }
    deinit { releases.count.withLock { $0 += 1 } }
}

private final class CompositeReleaseCounter: Sendable {
    let count = Mutex(0)
}
