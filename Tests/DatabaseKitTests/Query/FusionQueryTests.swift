import DatabaseKit
import DatabaseTypes
import Testing

@Persistable
private struct FusionPlanDocument {
    var id: String
    var title: String
}

private struct FusionPlanInput: FusionQueryInput {
    typealias Item = FusionPlanDocument

    let fusionInput: FusionInput
}

@Suite("Fusion query model")
struct FusionQueryTests {
    @Test("builder preserves semantic stages and lowers to SelectQuery")
    func builderPreservesStages() throws {
        let search = FusionPlanInput(
            fusionInput: FusionInput(
                operation: .index(
                    FusionIndexSource(
                        selection: .matching(
                            type: .text(.fullText),
                            fields: [FusionPlanDocument.fields.title.identity],
                            fieldMatch: .contains
                        ),
                        parameters: ["query": .string("database")]
                    )
                ),
                scoring: .annotation(name: "score", order: .higherIsBetter),
                limit: 100
            )
        )
        let vector = FusionPlanInput(
            fusionInput: FusionInput(
                operation: .index(
                    FusionIndexSource(
                        selection: .named(name: "documents_vector", type: .vector)
                    )
                ),
                scoring: .annotation(name: "distance", order: .lowerIsBetter)
            )
        )
        let filter = FusionPlanInput(
            fusionInput: FusionInput(
                operation: .filter(
                    .equal(.col("title"), .literal(.string("Database")))
                )
            )
        )

        let query = FusionQuery<FusionPlanDocument> {
            FusionStage {
                search
                vector
            }
            filter
        }
        .strategy(.weighted([0.75, 0.25]))
        .limit(20)

        try query.source.validate()
        #expect(query.source.stages.count == 2)
        #expect(query.source.stages[0].inputs.count == 2)
        #expect(query.source.stages[1].inputs.count == 1)
        #expect(query.selectQuery.source == .table(TableRef("FusionPlanDocument")))
        #expect(query.selectQuery.accessPath == .fusion(query.source))
        #expect(query.selectQuery.limit == 20)
    }

    @Test("plan validation rejects impossible candidate and weight contracts")
    func validationRejectsInvalidContracts() {
        let candidatesFirst = FusionSource(
            stages: [
                FusionStageSource(inputs: [
                    FusionInput(
                        operation: .order([SortKey(.col("title"))]),
                        scoring: .position,
                        requirement: .candidates
                    ),
                ]),
            ]
        )
        #expect(
            throws: FusionPlanValidationError.candidatesRequiredInFirstStage(input: 0)
        ) {
            try candidatesFirst.validate()
        }

        let invalidWeights = FusionSource(
            stages: [
                FusionStageSource(inputs: [
                    FusionInput(
                        operation: .order([SortKey(.col("title"))]),
                        scoring: .position
                    ),
                ]),
            ],
            strategy: .weighted([1, 0.5])
        )
        #expect(
            throws: FusionPlanValidationError.weightCount(expected: 1, actual: 2)
        ) {
            try invalidWeights.validate()
        }
    }

    @Test("referenced columns include Fusion selection, filter, and ordering")
    func referencedColumnsIncludeFusionOperations() {
        let source = FusionSource(
            stages: [
                FusionStageSource(inputs: [
                    FusionInput(
                        operation: .index(
                            FusionIndexSource(
                                selection: .matching(
                                    type: .text(.fullText),
                                    fields: [FieldIdentity(name: "body", number: 2)],
                                    fieldMatch: .exact
                                )
                            )
                        ),
                        scoring: .position
                    ),
                    FusionInput(
                        operation: .filter(
                            .equal(.col("status"), .literal(.string("active")))
                        )
                    ),
                    FusionInput(
                        operation: .order([SortKey(.col("createdAt"))])
                    ),
                ]),
            ]
        )
        let query = SelectQuery(
            projection: .all,
            source: .table(TableRef("documents")),
            accessPath: .fusion(source)
        )

        #expect(query.referencedColumns == Set([
            ColumnRef("body"),
            ColumnRef("status"),
            ColumnRef("createdAt"),
        ]))
    }
}
