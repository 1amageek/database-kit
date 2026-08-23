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
                        operation: .index(
                            FusionIndexSource(
                                selection: .named(
                                    name: "documents_vector",
                                    type: .vector
                                )
                            )
                        ),
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

        let invalidTraversal = FusionSource(
            stages: [
                FusionStageSource(inputs: [
                    FusionInput(
                        operation: .connected(
                            FusionConnectedSource(
                                edgeEntity: "Follow",
                                selection: .named(
                                    name: "follow_graph",
                                    type: .graph(.property)
                                ),
                                resultField: FieldIdentity(
                                    name: "userID",
                                    number: 2
                                ),
                                origin: "alice",
                                maximumHops: 0
                            )
                        ),
                        scoring: .annotation(
                            name: "hops",
                            order: .lowerIsBetter
                        )
                    ),
                ]),
            ]
        )
        #expect(
            throws: FusionPlanValidationError.zeroConnectedMaximumHops(
                stage: 0,
                input: 0
            )
        ) {
            try invalidTraversal.validate()
        }

        let mixedStage = FusionSource(
            stages: [
                FusionStageSource(inputs: [
                    FusionInput(
                        operation: .index(
                            FusionIndexSource(
                                selection: .named(
                                    name: "documents_vector",
                                    type: .vector
                                )
                            )
                        ),
                        scoring: .position
                    ),
                    FusionInput(
                        operation: .filter(.literal(.bool(true)))
                    ),
                ]),
            ]
        )
        #expect(
            throws: FusionPlanValidationError.mixedScoringStage(index: 0)
        ) {
            try mixedStage.validate()
        }
    }

    @Test("plan validation rejects operation and scoring mismatches")
    func validationRejectsOperationScoringMismatches() {
        let scoredFilter = FusionSource(stages: [
            FusionStageSource(inputs: [
                FusionInput(
                    operation: .filter(.literal(.bool(true))),
                    scoring: .position
                ),
            ]),
        ])
        #expect(
            throws: FusionPlanValidationError.invalidFilterScoring(
                stage: 0,
                input: 0
            )
        ) {
            try scoredFilter.validate()
        }

        let unorderedRank = FusionSource(stages: [
            FusionStageSource(inputs: [
                FusionInput(
                    operation: .index(
                        FusionIndexSource(
                            selection: .named(
                                name: "documents_vector",
                                type: .vector
                            )
                        )
                    ),
                    scoring: .position
                ),
            ]),
            FusionStageSource(inputs: [
                FusionInput(
                    operation: .order([SortKey(.col("title"))]),
                    scoring: .annotation(
                        name: "score",
                        order: .higherIsBetter
                    ),
                    requirement: .candidates
                ),
            ]),
        ])
        #expect(
            throws: FusionPlanValidationError.invalidOrderScoring(
                stage: 1,
                input: 0
            )
        ) {
            try unorderedRank.validate()
        }

        let unrestrictedRank = FusionSource(stages: [
            FusionStageSource(inputs: [
                FusionInput(
                    operation: .order([SortKey(.col("title"))]),
                    scoring: .position
                ),
            ]),
        ])
        #expect(
            throws: FusionPlanValidationError.orderRequiresCandidates(
                stage: 0,
                input: 0
            )
        ) {
            try unrestrictedRank.validate()
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
                ]),
                FusionStageSource(inputs: [
                    FusionInput(
                        operation: .filter(
                            .equal(.col("status"), .literal(.string("active")))
                        )
                    ),
                ]),
                FusionStageSource(inputs: [
                    FusionInput(
                        operation: .order([SortKey(.col("createdAt"))]),
                        scoring: .position,
                        requirement: .candidates
                    ),
                    FusionInput(
                        operation: .connected(
                            FusionConnectedSource(
                                edgeEntity: "Follow",
                                selection: .named(
                                    name: "follow_graph",
                                    type: .graph(.property)
                                ),
                                resultField: FieldIdentity(
                                    name: "userID",
                                    number: 5
                                ),
                                origin: "alice"
                            )
                        ),
                        scoring: .annotation(
                            name: "hops",
                            order: .lowerIsBetter
                        )
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
            ColumnRef("userID"),
        ]))
    }
}
