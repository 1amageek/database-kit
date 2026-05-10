import Foundation
import Testing
@testable import Core
import DatabaseClientProtocol
import QueryIR

@Suite("DatabaseKit E2E Tests")
struct DatabaseKitE2ETests {
    @Test("schema metadata and canonical query wire payload round-trip together")
    func schemaMetadataAndCanonicalQueryWirePayloadRoundTripTogether() throws {
        let schema = Schema([DatabaseKitE2EUser.self])
        let entity = try #require(schema.entity(for: DatabaseKitE2EUser.self))

        #expect(entity.name == "DatabaseKitE2EUser")
        #expect(entity.directoryComponents == [
            .staticPath("database-kit-e2e"),
            .staticPath("users")
        ])
        #expect(entity.indexes.map(\.name) == ["database_kit_e2e_user_email"])
        #expect(entity.indexes.first?.kindIdentifier == "scalar")
        #expect(entity.indexes.first?.fieldNames == ["email"])

        let query = SelectQuery(
            projection: .items([
                .column("id"),
                .column("email"),
                .column("age"),
            ]),
            source: .table(TableRef(table: DatabaseKitE2EUser.persistableType)),
            filter: .greaterThanOrEqual(
                .column(ColumnRef("age")),
                .literal(.int(20))
            ),
            orderBy: [
                SortKey(.column(ColumnRef("email")), direction: .ascending)
            ],
            limit: 10
        )
        let request = QueryRequest(
            statement: .select(query),
            options: ReadExecutionOptions(
                consistency: .snapshot,
                pageSize: 10,
                continuation: QueryContinuation("page-1")
            ),
            partitionValues: ["tenantID": "tenant-a"]
        )

        let requestEnvelope = ServiceEnvelope(
            operationID: "query",
            payload: try JSONEncoder().encode(request),
            metadata: ["traceID": "database-kit-e2e"]
        )
        let decodedEnvelope = try JSONDecoder().decode(
            ServiceEnvelope.self,
            from: try JSONEncoder().encode(requestEnvelope)
        )
        let decodedRequest = try JSONDecoder().decode(QueryRequest.self, from: decodedEnvelope.payload)

        #expect(decodedEnvelope.operationID == "query")
        #expect(decodedEnvelope.metadata["traceID"] == "database-kit-e2e")
        #expect(decodedRequest.options.consistency == .snapshot)
        #expect(decodedRequest.options.pageSize == 10)
        #expect(decodedRequest.options.continuation?.token == "page-1")
        #expect(decodedRequest.partitionValues == ["tenantID": "tenant-a"])
        #expect(decodedRequest.statement == .select(query))

        let response = QueryResponse(
            rows: [
                QueryRow(
                    fields: [
                        "id": .string("user-1"),
                        "email": .string("alice@example.com"),
                        "age": .int64(30),
                    ],
                    annotations: ["source": .string("database-kit-e2e")]
                )
            ],
            continuation: QueryContinuation("page-2"),
            metadata: ["entity": .string(entity.name)]
        )
        let responseEnvelope = ServiceEnvelope(
            responseTo: decodedEnvelope.requestID,
            operationID: "query",
            payload: try JSONEncoder().encode(response)
        )
        let decodedResponseEnvelope = try JSONDecoder().decode(
            ServiceEnvelope.self,
            from: try JSONEncoder().encode(responseEnvelope)
        )
        let decodedResponse = try JSONDecoder().decode(QueryResponse.self, from: decodedResponseEnvelope.payload)

        #expect(decodedResponseEnvelope.isError == false)
        #expect(decodedResponse.rows.first?.fields["email"] == .string("alice@example.com"))
        #expect(decodedResponse.rows.first?.annotations["source"] == .string("database-kit-e2e"))
        #expect(decodedResponse.continuation?.token == "page-2")
        #expect(decodedResponse.metadata["entity"] == .string("DatabaseKitE2EUser"))
    }

    @Test("command request and response preserve retry and effect contracts")
    func commandRequestAndResponsePreserveRetryAndEffectContracts() throws {
        let payload = try JSONEncoder().encode(["leadID": "lead-1"])
        let request = CommandRequest(
            commandID: "crm.convertLead",
            idempotencyKey: "convert-lead-1",
            payload: payload,
            preconditions: [
                WritePreconditionEntry(
                    key: RecordKey(entityName: "Lead", id: .string("lead-1")),
                    precondition: .matchesStored(RecordVersionToken("version-1"))
                )
            ],
            metadata: ["tenantID": "tenant-a"]
        )
        let envelope = ServiceEnvelope(
            operationID: "command",
            payload: try JSONEncoder().encode(request)
        )

        let decodedEnvelope = try JSONDecoder().decode(
            ServiceEnvelope.self,
            from: try JSONEncoder().encode(envelope)
        )
        let decodedRequest = try JSONDecoder().decode(CommandRequest.self, from: decodedEnvelope.payload)

        #expect(decodedEnvelope.operationID == "command")
        #expect(decodedRequest.commandID == "crm.convertLead")
        #expect(decodedRequest.idempotencyKey?.value == "convert-lead-1")
        #expect(decodedRequest.preconditions.first?.precondition.kind == .matchesStored)
        #expect(decodedRequest.preconditions.first?.precondition.version?.value == "version-1")
        #expect(decodedRequest.metadata["tenantID"] == "tenant-a")

        let responsePayload = try JSONEncoder().encode(["accountID": "account-1"])
        let response = CommandResponse(
            status: "applied",
            payload: responsePayload,
            effects: [
                .recordVersionChanged(
                    key: RecordKey(entityName: "Account", id: .string("account-1")),
                    version: RecordVersionToken("account-version-1")
                )
            ],
            replayed: true
        )
        let responseEnvelope = ServiceEnvelope(
            responseTo: decodedEnvelope.requestID,
            operationID: "command",
            payload: try JSONEncoder().encode(response)
        )
        let decodedResponseEnvelope = try JSONDecoder().decode(
            ServiceEnvelope.self,
            from: try JSONEncoder().encode(responseEnvelope)
        )
        let decodedResponse = try JSONDecoder().decode(CommandResponse.self, from: decodedResponseEnvelope.payload)

        #expect(decodedResponseEnvelope.isError == false)
        #expect(decodedResponse.status == "applied")
        #expect(decodedResponse.replayed == true)
        #expect(decodedResponse.effects.first?.kind == CommandEffectKind.recordVersionChanged)
        #expect(decodedResponse.effects.first?.key?.entityName == "Account")
        #expect(decodedResponse.effects.first?.metadata["version"] == .string("account-version-1"))
    }

    @Test("partitioned save changes and fusion access path preserve structured wire contracts")
    func partitionedSaveChangesAndFusionAccessPathPreserveStructuredWireContracts() throws {
        let schema = Schema([DatabaseKitE2EOrder.self])
        let entity = try #require(schema.entity(for: DatabaseKitE2EOrder.self))

        #expect(entity.hasDynamicDirectory == true)
        #expect(entity.dynamicFieldNames == ["tenantID"])
        #expect(try entity.resolvedDirectoryPath(partitionValues: ["tenantID": "tenant-a"]) == [
            "database-kit-e2e",
            "tenant-a",
            "orders",
        ])
        #expect(throws: DirectoryPathError.self) {
            try entity.resolvedDirectoryPath()
        }

        let saveRequest = SaveRequest(changes: [
            ChangeSet.Change(
                entityName: DatabaseKitE2EOrder.persistableType,
                id: "order-1",
                operation: .insert,
                fields: [
                    "id": .string("order-1"),
                    "tenantID": .string("tenant-a"),
                    "status": .string("open"),
                    "total": .double(42.5),
                ],
                partitionValues: ["tenantID": "tenant-a"]
            ),
            ChangeSet.Change(
                entityName: DatabaseKitE2EOrder.persistableType,
                id: "order-2",
                operation: .update,
                fields: [
                    "id": .string("order-2"),
                    "tenantID": .string("tenant-a"),
                    "status": .string("paid"),
                    "total": .double(80.0),
                ],
                partitionValues: ["tenantID": "tenant-a"]
            ),
            ChangeSet.Change(
                entityName: DatabaseKitE2EOrder.persistableType,
                id: "order-3",
                operation: .delete,
                partitionValues: ["tenantID": "tenant-b"]
            ),
        ], preconditions: [
            WritePreconditionEntry(
                key: RecordKey(
                    entityName: DatabaseKitE2EOrder.persistableType,
                    id: .string("order-1"),
                    partitionValues: ["tenantID": "tenant-a"]
                ),
                precondition: .notExists
            )
        ], idempotencyKey: "partitioned-save-1", clientMutationID: "mutation-1")
        let saveEnvelope = ServiceEnvelope(
            operationID: "save",
            payload: try JSONEncoder().encode(saveRequest),
            metadata: ["traceID": "partitioned-save"]
        )
        let decodedSaveEnvelope = try JSONDecoder().decode(
            ServiceEnvelope.self,
            from: try JSONEncoder().encode(saveEnvelope)
        )
        let decodedSaveRequest = try JSONDecoder().decode(SaveRequest.self, from: decodedSaveEnvelope.payload)

        let operations = decodedSaveRequest.changes.map { $0.operation }
        #expect(decodedSaveEnvelope.metadata["traceID"] == "partitioned-save")
        #expect(operations == [
            ChangeSet.Change.Operation.insert,
            .update,
            .delete,
        ])
        #expect(decodedSaveRequest.changes[0].partitionValues == ["tenantID": "tenant-a"])
        #expect(decodedSaveRequest.changes[1].fields?["status"] == FieldValue.string("paid"))
        #expect(decodedSaveRequest.changes[2].fields == nil)
        #expect(decodedSaveRequest.changes[2].partitionValues == ["tenantID": "tenant-b"])
        #expect(decodedSaveRequest.preconditions.count == 1)
        #expect(decodedSaveRequest.preconditions.first?.key.id == .string("order-1"))
        #expect(decodedSaveRequest.preconditions.first?.precondition.kind == .notExists)
        #expect(decodedSaveRequest.idempotencyKey?.value == "partitioned-save-1")
        #expect(decodedSaveRequest.clientMutationID == "mutation-1")

        let legacySaveRequest = try JSONDecoder().decode(
            SaveRequest.self,
            from: #"{"changes":[]}"#.data(using: .utf8)!
        )
        #expect(legacySaveRequest.changes.isEmpty)
        #expect(legacySaveRequest.preconditions.isEmpty)
        #expect(legacySaveRequest.idempotencyKey == nil)
        #expect(legacySaveRequest.clientMutationID == nil)

        let fusionSource = FusionSource(
            inputs: [
                IndexScanSource(
                    indexName: "database_kit_e2e_order_status",
                    kindIdentifier: "scalar",
                    parameters: [
                        "equals": .object([
                            "status": .string("open"),
                            "tenantID": .string("tenant-a"),
                        ]),
                    ]
                ),
                IndexScanSource(
                    indexName: "database_kit_e2e_order_total",
                    kindIdentifier: "rank",
                    parameters: [
                        "range": .object([
                            "minimum": .double(25.0),
                            "maximum": .double(100.0),
                        ]),
                        "boosts": .array([.double(0.7), .double(0.3)]),
                    ]
                ),
            ],
            strategyIdentifier: "weighted-reciprocal-rank",
            parameters: [
                "weights": .object([
                    "status": .double(0.65),
                    "total": .double(0.35),
                ]),
                "topK": .int(25),
            ],
            identityField: "id"
        )
        let query = SelectQuery(
            projection: .items([
                .column("id"),
                .column("status"),
                .column("total"),
            ]),
            source: .logical(LogicalSourceRef(
                kindIdentifier: BuiltinLogicalSourceKind.polymorphic,
                identifier: "database-kit-e2e-orders",
                alias: "orders"
            )),
            accessPath: .fusion(fusionSource),
            filter: .and(
                .equal(.column(ColumnRef("tenantID")), .literal(.string("tenant-a"))),
                .greaterThan(.column(ColumnRef("total")), .literal(.double(25.0)))
            ),
            orderBy: [
                SortKey(.column(ColumnRef("total")), direction: .descending),
                SortKey(.column(ColumnRef("id")), direction: .ascending),
            ],
            limit: 25,
            offset: 5,
            distinct: true
        )
        let request = QueryRequest(
            statement: .select(query),
            options: ReadExecutionOptions(
                consistency: .serializable,
                pageSize: 25,
                continuation: QueryContinuation("offset-5")
            ),
            partitionValues: ["tenantID": "tenant-a"]
        )
        let decodedRequest = try JSONDecoder().decode(
            QueryRequest.self,
            from: try JSONEncoder().encode(request)
        )

        #expect(decodedRequest.partitionValues == ["tenantID": "tenant-a"])
        #expect(decodedRequest.options.continuation?.token == "offset-5")
        #expect(decodedRequest.statement == .select(query))

        guard case .select(let decodedQuery) = decodedRequest.statement,
              case .fusion(let decodedFusion)? = decodedQuery.accessPath else {
            Issue.record("Expected a fusion access path")
            return
        }
        #expect(decodedFusion.inputs.count == 2)
        #expect(decodedFusion.strategyIdentifier == "weighted-reciprocal-rank")
        #expect(decodedFusion.parameters["topK"] == .int(25))
        #expect(decodedFusion.inputs[0].parameters["equals"]?.objectValue?["status"] == .string("open"))
        #expect(decodedFusion.inputs[1].parameters["boosts"]?.arrayValue == [.double(0.7), .double(0.3)])
    }

    @Test("aggregate query wire payload preserves group by having and projection aliases")
    func aggregateQueryWirePayloadPreservesGroupByHavingAndProjectionAliases() throws {
        let totalExpression = QueryIR.Expression.aggregate(
            .sum(.column(ColumnRef("total")), distinct: false)
        )
        let countExpression = QueryIR.Expression.aggregate(
            .count(.column(ColumnRef("id")), distinct: true)
        )
        let query = SelectQuery(
            projection: .items([
                ProjectionItem(.column(ColumnRef("tenantID")), alias: "tenant"),
                ProjectionItem(.column(ColumnRef("status")), alias: "state"),
                ProjectionItem(totalExpression, alias: "totalRevenue"),
                ProjectionItem(countExpression, alias: "orderCount"),
            ]),
            source: .table(TableRef(table: DatabaseKitE2EOrder.persistableType)),
            filter: .greaterThanOrEqual(
                .column(ColumnRef("total")),
                .literal(.double(10.0))
            ),
            groupBy: [
                .column(ColumnRef("tenantID")),
                .column(ColumnRef("status")),
            ],
            having: .greaterThan(
                totalExpression,
                .literal(.double(100.0))
            ),
            orderBy: [
                SortKey(totalExpression, direction: .descending),
                SortKey(.column(ColumnRef("tenantID")), direction: .ascending),
            ],
            limit: 20,
            offset: 10,
            distinct: true
        )
        let request = QueryRequest(
            statement: .select(query),
            options: ReadExecutionOptions(
                consistency: .serializable,
                pageSize: 20,
                continuation: QueryContinuation("aggregate-page-2")
            ),
            partitionValues: ["tenantID": "tenant-a"]
        )

        let decodedRequest = try JSONDecoder().decode(
            QueryRequest.self,
            from: try JSONEncoder().encode(request)
        )

        #expect(decodedRequest.statement == .select(query))
        #expect(decodedRequest.options.continuation?.token == "aggregate-page-2")
        #expect(decodedRequest.partitionValues == ["tenantID": "tenant-a"])

        guard case .select(let decodedQuery) = decodedRequest.statement,
              case .items(let projectionItems) = decodedQuery.projection else {
            Issue.record("Expected aggregate select query")
            return
        }

        #expect(projectionItems.map(\.alias) == [
            "tenant",
            "state",
            "totalRevenue",
            "orderCount",
        ])
        #expect(decodedQuery.groupBy == [
            .column(ColumnRef("tenantID")),
            .column(ColumnRef("status")),
        ])
        #expect(decodedQuery.having == .greaterThan(totalExpression, .literal(.double(100.0))))
        #expect(decodedQuery.orderBy == [
            SortKey(totalExpression, direction: .descending),
            SortKey(.column(ColumnRef("tenantID")), direction: .ascending),
        ])
        #expect(decodedQuery.limit == 20)
        #expect(decodedQuery.offset == 10)
        #expect(decodedQuery.distinct == true)
    }

    @Test("relational query wire payload preserves CTE subquery join values and nested predicates")
    func relationalQueryWirePayloadPreservesCTESubqueryJoinValuesAndNestedPredicates() throws {
        let recentOrders = SelectQuery(
            projection: .items([
                ProjectionItem(.column(ColumnRef("id"))),
                ProjectionItem(.column(ColumnRef("tenantID"))),
                ProjectionItem(.column(ColumnRef("status"))),
                ProjectionItem(.column(ColumnRef("total"))),
            ]),
            source: .table(TableRef(table: DatabaseKitE2EOrder.persistableType, alias: "orders")),
            filter: .and(
                .greaterThanOrEqual(.column(ColumnRef(table: "orders", column: "total")), .literal(.double(50.0))),
                .inList(
                    .column(ColumnRef(table: "orders", column: "status")),
                    values: [.literal(.string("open")), .literal(.string("paid"))]
                )
            )
        )
        let allowedTenants = DataSource.values(
            [
                [.string("tenant-a"), .string("gold")],
                [.string("tenant-b"), .string("silver")],
            ],
            columnNames: ["tenantID", "tier"]
        )
        let joinedSource = DataSource.join(JoinClause(
            type: .left,
            left: .subquery(recentOrders, alias: "recent"),
            right: allowedTenants,
            condition: .on(.equal(
                .column(ColumnRef(table: "recent", column: "tenantID")),
                .column(ColumnRef(table: "allowed", column: "tenantID"))
            ))
        ))
        let highValueSubquery = SelectQuery(
            projection: .items([
                ProjectionItem(.column(ColumnRef("id")))
            ]),
            source: .table(TableRef(table: DatabaseKitE2EOrder.persistableType)),
            filter: .greaterThan(.column(ColumnRef("total")), .literal(.double(90.0)))
        )
        let query = SelectQuery(
            projection: .items([
                ProjectionItem(.column(ColumnRef(table: "recent", column: "id")), alias: "orderID"),
                ProjectionItem(.column(ColumnRef(table: "recent", column: "tenantID")), alias: "tenant"),
                ProjectionItem(.column(ColumnRef(table: "recent", column: "total")), alias: "total"),
                ProjectionItem(
                    .caseWhen(
                        cases: [
                            CaseWhenPair(
                                condition: .greaterThan(
                                    .column(ColumnRef(table: "recent", column: "total")),
                                    .literal(.double(100.0))
                                ),
                                result: .literal(.string("priority"))
                            )
                        ],
                        elseResult: .literal(.string("standard"))
                    ),
                    alias: "routing"
                ),
            ]),
            source: joinedSource,
            filter: .or(
                .inSubquery(.column(ColumnRef(table: "recent", column: "id")), subquery: highValueSubquery),
                .isNotNull(.column(ColumnRef(table: "allowed", column: "tier")))
            ),
            orderBy: [
                SortKey(.column(ColumnRef(table: "recent", column: "total")), direction: .descending, nulls: .last)
            ],
            limit: 50,
            subqueries: [
                NamedSubquery(
                    name: "recent_orders",
                    columns: ["id", "tenantID", "status", "total"],
                    query: recentOrders,
                    materialized: .notMaterialized
                )
            ]
        )
        let request = QueryRequest(
            statement: .select(query),
            options: ReadExecutionOptions(
                consistency: .snapshot,
                pageSize: 50,
                continuation: QueryContinuation("joined-page")
            ),
            partitionValues: ["tenantID": "tenant-a"]
        )

        let decodedRequest = try JSONDecoder().decode(
            QueryRequest.self,
            from: try JSONEncoder().encode(request)
        )

        #expect(decodedRequest.statement == .select(query))
        #expect(decodedRequest.partitionValues == ["tenantID": "tenant-a"])
        #expect(decodedRequest.options.continuation?.token == "joined-page")

        guard case .select(let decodedQuery) = decodedRequest.statement,
              case .join(let decodedJoin) = decodedQuery.source,
              case .values(let decodedValues, let decodedColumnNames) = decodedJoin.right else {
            Issue.record("Expected joined source with values")
            return
        }

        #expect(decodedQuery.subqueries?.first?.name == "recent_orders")
        #expect(decodedQuery.subqueries?.first?.materialized == .notMaterialized)
        #expect(decodedJoin.type == .left)
        #expect(decodedValues == [
            [.string("tenant-a"), .string("gold")],
            [.string("tenant-b"), .string("silver")],
        ])
        #expect(decodedColumnNames == ["tenantID", "tier"])
        #expect(decodedQuery.filter == query.filter)
        #expect(decodedQuery.orderBy == query.orderBy)
    }

    @Test("schema response preserves polymorphic groups enum metadata and index metadata")
    func schemaResponsePreservesPolymorphicGroupsEnumMetadataAndIndexMetadata() throws {
        let schema = Schema([
            DatabaseKitE2EArticle.self,
            DatabaseKitE2EReport.self,
        ])
        let response = SchemaResponse(
            entities: schema.entities,
            polymorphicGroups: schema.polymorphicGroups
        )

        let decodedResponse = try JSONDecoder().decode(
            SchemaResponse.self,
            from: try JSONEncoder().encode(response)
        )
        let article = try #require(decodedResponse.entities.first { $0.name == DatabaseKitE2EArticle.persistableType })
        let sharedGroup = try #require(decodedResponse.polymorphicGroups.first {
            $0.identifier == "DatabaseKitE2EReadableDocument"
        })
        let articleStatusIndex = try #require(article.indexes.first { $0.name == "database_kit_e2e_article_status" })
        let sharedTitleIndex = try #require(sharedGroup.indexes.first { $0.name == "database_kit_e2e_document_title" })

        #expect(article.enumMetadata["status"] == ["draft", "published", "archived"])
        #expect(article.directoryComponents == [
            .staticPath("database-kit-e2e"),
            .staticPath("articles"),
        ])
        #expect(articleStatusIndex.unique == true)
        #expect(articleStatusIndex.storedFieldNames == ["title"])
        #expect(articleStatusIndex.commonMetadata["unique"] == .bool(true))
        #expect(sharedGroup.directoryComponents == [
            DirectoryComponentCatalog.staticPath("database-kit-e2e"),
            DirectoryComponentCatalog.staticPath("documents"),
        ])
        #expect(sharedGroup.memberTypeNames == [
            DatabaseKitE2EArticle.persistableType,
            DatabaseKitE2EReport.persistableType,
        ])
        #expect(sharedTitleIndex.fieldNames == ["title"])
        #expect(sharedTitleIndex.kindIdentifier == "scalar")
        #expect(sharedTitleIndex.commonMetadata["userMetadata.scope"] == .string("shared"))
    }

    @Test("field value wire payload preserves binary arrays and nulls")
    func fieldValueWirePayloadPreservesBinaryArraysAndNulls() throws {
        let blob = Data([0x01, 0x02, 0x03, 0x04])
        let saveRequest = SaveRequest(changes: [
            ChangeSet.Change(
                entityName: DatabaseKitE2EArticle.persistableType,
                id: "article-binary-1",
                operation: .insert,
                fields: [
                    "id": .string("article-binary-1"),
                    "title": .string("Binary Article"),
                    "attachment": .data(blob),
                    "tags": .array([.string("alpha"), .string("beta")]),
                    "note": .null,
                ]
            )
        ])
        let decodedSaveRequest = try JSONDecoder().decode(
            SaveRequest.self,
            from: try JSONEncoder().encode(saveRequest)
        )
        let decodedFields = try #require(decodedSaveRequest.changes.first?.fields)

        #expect(decodedFields["attachment"] == .data(blob))
        #expect(decodedFields["tags"] == .array([.string("alpha"), .string("beta")]))
        #expect(decodedFields["note"] == .null)

        let response = QueryResponse(
            rows: [
                QueryRow(
                    fields: [
                        "id": .string("article-binary-1"),
                        "attachment": .data(blob),
                        "tags": .array([.string("alpha"), .string("beta")]),
                        "note": .null,
                    ],
                    annotations: [
                        "preview": .data(blob.prefix(2)),
                        "segments": .array([.int64(1), .int64(2), .int64(3)]),
                    ]
                )
            ],
            metadata: [
                "payloadKind": .string("binary"),
                "checksums": .array([.int64(7), .int64(9)]),
                "missing": .null,
            ]
        )
        let decodedResponse = try JSONDecoder().decode(
            QueryResponse.self,
            from: try JSONEncoder().encode(response)
        )

        #expect(decodedResponse.rows.first?.fields["attachment"] == .data(blob))
        #expect(decodedResponse.rows.first?.fields["tags"]?.arrayValue == [.string("alpha"), .string("beta")])
        #expect(decodedResponse.rows.first?.annotations["preview"] == .data(blob.prefix(2)))
        #expect(decodedResponse.metadata["checksums"] == .array([.int64(7), .int64(9)]))
        #expect(decodedResponse.metadata["missing"] == .null)
    }

    @Test("service envelope error payload preserves typed code message and metadata")
    func serviceEnvelopeErrorPayloadPreservesTypedCodeMessageAndMetadata() throws {
        let envelope = ServiceEnvelope(
            responseTo: "request-1",
            operationID: "query",
            errorCode: "QUERY_REJECTED",
            errorMessage: "Query rejected by policy",
            metadata: [
                "traceID": "database-kit-error-e2e",
                "retryable": "false",
            ]
        )
        let decodedEnvelope = try JSONDecoder().decode(
            ServiceEnvelope.self,
            from: try JSONEncoder().encode(envelope)
        )

        #expect(decodedEnvelope.requestID == "request-1")
        #expect(decodedEnvelope.operationID == "query")
        #expect(decodedEnvelope.isError == true)
        #expect(decodedEnvelope.errorCode == "QUERY_REJECTED")
        #expect(decodedEnvelope.errorMessage == "Query rejected by policy")
        #expect(decodedEnvelope.metadata["traceID"] == "database-kit-error-e2e")
        #expect(decodedEnvelope.metadata["retryable"] == "false")
        #expect(decodedEnvelope.payload.isEmpty)
    }

    @Test("decoded schema response stays wire-safe without runtime type metadata")
    func decodedSchemaResponseStaysWireSafeWithoutRuntimeTypeMetadata() throws {
        let schema = Schema([
            DatabaseKitE2EArticle.self,
            DatabaseKitE2EReport.self,
        ])
        let decodedResponse = try JSONDecoder().decode(
            SchemaResponse.self,
            from: try JSONEncoder().encode(
                SchemaResponse(
                    entities: schema.entities,
                    polymorphicGroups: schema.polymorphicGroups
                )
            )
        )

        let article = try #require(decodedResponse.entities.first { $0.name == DatabaseKitE2EArticle.persistableType })

        #expect(article.persistableType == nil)
        #expect(article.indexDescriptors.isEmpty)
        #expect(decodedResponse.polymorphicGroups.first?.memberTypeNames == [
            DatabaseKitE2EArticle.persistableType,
            DatabaseKitE2EReport.persistableType,
        ])
    }

    @Test("manual wire schema metadata decodes dynamic directories and index options")
    func manualWireSchemaMetadataDecodesDynamicDirectoriesAndIndexOptions() throws {
        let entity = Schema.Entity(
            name: "WireOrder",
            fields: [
                FieldSchema(name: "id", fieldNumber: 1, type: .string),
                FieldSchema(name: "tenantID", fieldNumber: 2, type: .string),
                FieldSchema(name: "status", fieldNumber: 3, type: .string),
            ],
            directoryComponents: [
                .staticPath("wire"),
                .dynamicField(fieldName: "tenantID"),
                .staticPath("orders"),
            ],
            indexes: [
                AnyIndexDescriptor(
                    name: "wire_order_status",
                    kind: AnyIndexKind(
                        identifier: "scalar",
                        subspaceStructure: .flat,
                        fieldNames: ["status"],
                        metadata: [:]
                    ),
                    commonMetadata: [
                        "unique": .bool(false),
                        "sparse": .bool(true),
                        "storedFieldNames": .stringArray(["tenantID"]),
                    ]
                )
            ]
        )
        let group = PolymorphicGroup(
            identifier: "WireDocument",
            directoryComponents: [.staticPath("wire-documents")],
            indexes: [
                AnyIndexDescriptor(
                    name: "wire_document_title",
                    kind: AnyIndexKind(
                        identifier: "scalar",
                        subspaceStructure: .flat,
                        fieldNames: ["title"],
                        metadata: ["boost": .double(1.5)]
                    ),
                    commonMetadata: ["unique": .bool(false)]
                )
            ],
            memberTypeNames: ["WireArticle", "WireReport"]
        )
        let decodedResponse = try JSONDecoder().decode(
            SchemaResponse.self,
            from: try JSONEncoder().encode(
                SchemaResponse(
                    entities: [entity],
                    polymorphicGroups: [group]
                )
            )
        )

        let decodedEntity = try #require(decodedResponse.entities.first)
        let decodedGroup = try #require(decodedResponse.polymorphicGroups.first)

        #expect(try decodedEntity.resolvedDirectoryPath(partitionValues: ["tenantID": "tenant-a"]) == [
            "wire",
            "tenant-a",
            "orders",
        ])
        #expect(decodedEntity.indexes.first?.sparse == true)
        #expect(decodedEntity.indexes.first?.storedFieldNames == ["tenantID"])
        #expect(decodedGroup.indexes.first?.kind.metadata["boost"] == .double(1.5))
        #expect(decodedGroup.memberTypeNames == ["WireArticle", "WireReport"])
    }
}

private enum DatabaseKitE2EArticleStatus: String, PersistableEnum {
    case draft
    case published
    case archived
}

private protocol DatabaseKitE2EReadableDocument: Polymorphable {
    var id: String { get }
    var title: String { get }
}

extension DatabaseKitE2EReadableDocument {
    static var polymorphableType: String { "DatabaseKitE2EReadableDocument" }

    static var polymorphicDirectoryPathComponents: [any DirectoryPathElement] {
        [Path("database-kit-e2e"), Path("documents")]
    }

    static var polymorphicIndexDescriptors: [IndexDescriptor] {
        [
            IndexDescriptor(
                name: "database_kit_e2e_document_title",
                keyPaths: [\Self.title],
                kind: ScalarIndexKind<Self>(fields: [\Self.title]),
                commonOptions: .init(metadata: ["scope": "shared"])
            )
        ]
    }
}

@Persistable
private struct DatabaseKitE2EUser {
    #Directory<DatabaseKitE2EUser>("database-kit-e2e", "users")
    #Index(
        ScalarIndexKind<DatabaseKitE2EUser>(fields: [\.email]),
        name: "database_kit_e2e_user_email"
    )

    var email: String
    var age: Int
}

@Persistable
private struct DatabaseKitE2EOrder {
    #Directory<DatabaseKitE2EOrder>(
        "database-kit-e2e",
        Field<DatabaseKitE2EOrder>(\.tenantID),
        "orders",
        layer: .partition
    )
    #Index(
        ScalarIndexKind<DatabaseKitE2EOrder>(fields: [\.status]),
        name: "database_kit_e2e_order_status"
    )
    #Index(
        ScalarIndexKind<DatabaseKitE2EOrder>(fields: [\.total]),
        name: "database_kit_e2e_order_total"
    )

    var id: String = UUID().uuidString
    var tenantID: String
    var status: String
    var total: Double
}

@Persistable
private struct DatabaseKitE2EArticle: DatabaseKitE2EReadableDocument {
    #Directory<DatabaseKitE2EArticle>("database-kit-e2e", "articles")
    #Index(
        ScalarIndexKind<DatabaseKitE2EArticle>(fields: [\.status]),
        storedFields: [\DatabaseKitE2EArticle.title],
        unique: true,
        name: "database_kit_e2e_article_status"
    )

    var id: String = UUID().uuidString
    var title: String
    var status: DatabaseKitE2EArticleStatus
}

@Persistable
private struct DatabaseKitE2EReport: DatabaseKitE2EReadableDocument {
    #Directory<DatabaseKitE2EReport>("database-kit-e2e", "reports")

    var id: String = UUID().uuidString
    var title: String
    var summary: String
}
