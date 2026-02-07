/// QueryStatement+Codable.swift
/// Codable conformance for QueryStatement and related enums using tag-based encoding
///
/// Encoding format:
/// ```json
/// {"tag": "select", "query": {...}}
/// {"tag": "dropGraph", "name": "graphName"}
/// ```

import Foundation

// MARK: - QueryStatement + Codable

extension QueryStatement: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case query
        case name
        case silent
    }

    private enum Tag: String, Codable {
        case select
        case insert
        case update
        case delete
        case createGraph
        case dropGraph
        case insertData
        case deleteData
        case deleteInsert
        case load
        case clear
        case createSPARQLGraph
        case dropSPARQLGraph
        case construct
        case ask
        case describe
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .select(let query):
            try container.encode(Tag.select, forKey: .tag)
            try container.encode(query, forKey: .query)
        case .insert(let query):
            try container.encode(Tag.insert, forKey: .tag)
            try container.encode(query, forKey: .query)
        case .update(let query):
            try container.encode(Tag.update, forKey: .tag)
            try container.encode(query, forKey: .query)
        case .delete(let query):
            try container.encode(Tag.delete, forKey: .tag)
            try container.encode(query, forKey: .query)
        case .createGraph(let stmt):
            try container.encode(Tag.createGraph, forKey: .tag)
            try container.encode(stmt, forKey: .query)
        case .dropGraph(let name):
            try container.encode(Tag.dropGraph, forKey: .tag)
            try container.encode(name, forKey: .name)
        case .insertData(let query):
            try container.encode(Tag.insertData, forKey: .tag)
            try container.encode(query, forKey: .query)
        case .deleteData(let query):
            try container.encode(Tag.deleteData, forKey: .tag)
            try container.encode(query, forKey: .query)
        case .deleteInsert(let query):
            try container.encode(Tag.deleteInsert, forKey: .tag)
            try container.encode(query, forKey: .query)
        case .load(let query):
            try container.encode(Tag.load, forKey: .tag)
            try container.encode(query, forKey: .query)
        case .clear(let query):
            try container.encode(Tag.clear, forKey: .tag)
            try container.encode(query, forKey: .query)
        case .createSPARQLGraph(let name, let silent):
            try container.encode(Tag.createSPARQLGraph, forKey: .tag)
            try container.encode(name, forKey: .name)
            try container.encode(silent, forKey: .silent)
        case .dropSPARQLGraph(let name, let silent):
            try container.encode(Tag.dropSPARQLGraph, forKey: .tag)
            try container.encode(name, forKey: .name)
            try container.encode(silent, forKey: .silent)
        case .construct(let query):
            try container.encode(Tag.construct, forKey: .tag)
            try container.encode(query, forKey: .query)
        case .ask(let query):
            try container.encode(Tag.ask, forKey: .tag)
            try container.encode(query, forKey: .query)
        case .describe(let query):
            try container.encode(Tag.describe, forKey: .tag)
            try container.encode(query, forKey: .query)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .select:
            self = .select(try container.decode(SelectQuery.self, forKey: .query))
        case .insert:
            self = .insert(try container.decode(InsertQuery.self, forKey: .query))
        case .update:
            self = .update(try container.decode(UpdateQuery.self, forKey: .query))
        case .delete:
            self = .delete(try container.decode(DeleteQuery.self, forKey: .query))
        case .createGraph:
            self = .createGraph(try container.decode(CreateGraphStatement.self, forKey: .query))
        case .dropGraph:
            self = .dropGraph(try container.decode(String.self, forKey: .name))
        case .insertData:
            self = .insertData(try container.decode(InsertDataQuery.self, forKey: .query))
        case .deleteData:
            self = .deleteData(try container.decode(DeleteDataQuery.self, forKey: .query))
        case .deleteInsert:
            self = .deleteInsert(try container.decode(DeleteInsertQuery.self, forKey: .query))
        case .load:
            self = .load(try container.decode(LoadQuery.self, forKey: .query))
        case .clear:
            self = .clear(try container.decode(ClearQuery.self, forKey: .query))
        case .createSPARQLGraph:
            let name = try container.decode(String.self, forKey: .name)
            let silent = try container.decode(Bool.self, forKey: .silent)
            self = .createSPARQLGraph(name, silent: silent)
        case .dropSPARQLGraph:
            let name = try container.decode(String.self, forKey: .name)
            let silent = try container.decode(Bool.self, forKey: .silent)
            self = .dropSPARQLGraph(name, silent: silent)
        case .construct:
            self = .construct(try container.decode(ConstructQuery.self, forKey: .query))
        case .ask:
            self = .ask(try container.decode(AskQuery.self, forKey: .query))
        case .describe:
            self = .describe(try container.decode(DescribeQuery.self, forKey: .query))
        }
    }
}

// MARK: - OnConflictAction + Codable

extension OnConflictAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case assignments
        case `where`
    }

    private enum Tag: String, Codable {
        case doNothing
        case doUpdate
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .doNothing:
            try container.encode(Tag.doNothing, forKey: .tag)
        case .doUpdate(let assignments, let whereExpr):
            try container.encode(Tag.doUpdate, forKey: .tag)
            try container.encode(assignments, forKey: .assignments)
            try container.encodeIfPresent(whereExpr, forKey: .where)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .doNothing:
            self = .doNothing
        case .doUpdate:
            let assignments = try container.decode([Assignment].self, forKey: .assignments)
            let whereExpr = try container.decodeIfPresent(Expression.self, forKey: .where)
            self = .doUpdate(assignments: assignments, where: whereExpr)
        }
    }
}

// MARK: - InsertSource + Codable

extension InsertSource: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case rows
        case query
    }

    private enum Tag: String, Codable {
        case values
        case select
        case defaultValues
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .values(let rows):
            try container.encode(Tag.values, forKey: .tag)
            try container.encode(rows, forKey: .rows)
        case .select(let query):
            try container.encode(Tag.select, forKey: .tag)
            try container.encode(query, forKey: .query)
        case .defaultValues:
            try container.encode(Tag.defaultValues, forKey: .tag)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .values:
            self = .values(try container.decode([[Expression]].self, forKey: .rows))
        case .select:
            self = .select(try container.decode(SelectQuery.self, forKey: .query))
        case .defaultValues:
            self = .defaultValues
        }
    }
}

// MARK: - LabelExpression + Codable

extension LabelExpression: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case value
        case expressions
    }

    private enum Tag: String, Codable {
        case single
        case column
        case or
        case and
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .single(let value):
            try container.encode(Tag.single, forKey: .tag)
            try container.encode(value, forKey: .value)
        case .column(let value):
            try container.encode(Tag.column, forKey: .tag)
            try container.encode(value, forKey: .value)
        case .or(let expressions):
            try container.encode(Tag.or, forKey: .tag)
            try container.encode(expressions, forKey: .expressions)
        case .and(let expressions):
            try container.encode(Tag.and, forKey: .tag)
            try container.encode(expressions, forKey: .expressions)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .single:
            self = .single(try container.decode(String.self, forKey: .value))
        case .column:
            self = .column(try container.decode(String.self, forKey: .value))
        case .or:
            self = .or(try container.decode([LabelExpression].self, forKey: .expressions))
        case .and:
            self = .and(try container.decode([LabelExpression].self, forKey: .expressions))
        }
    }
}

// MARK: - PropertiesSpec + Codable

extension PropertiesSpec: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case columns
    }

    private enum Tag: String, Codable {
        case all
        case none
        case columns
        case allExcept
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all:
            try container.encode(Tag.all, forKey: .tag)
        case .none:
            try container.encode(Tag.none, forKey: .tag)
        case .columns(let columns):
            try container.encode(Tag.columns, forKey: .tag)
            try container.encode(columns, forKey: .columns)
        case .allExcept(let columns):
            try container.encode(Tag.allExcept, forKey: .tag)
            try container.encode(columns, forKey: .columns)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .all:
            self = .all
        case .none:
            self = .none
        case .columns:
            self = .columns(try container.decode([String].self, forKey: .columns))
        case .allExcept:
            self = .allExcept(try container.decode([String].self, forKey: .columns))
        }
    }
}

// MARK: - ClearTarget + Codable

extension ClearTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag
        case name
    }

    private enum Tag: String, Codable {
        case graph
        case `default`
        case named
        case all
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .graph(let name):
            try container.encode(Tag.graph, forKey: .tag)
            try container.encode(name, forKey: .name)
        case .default:
            try container.encode(Tag.default, forKey: .tag)
        case .named:
            try container.encode(Tag.named, forKey: .tag)
        case .all:
            try container.encode(Tag.all, forKey: .tag)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(Tag.self, forKey: .tag)
        switch tag {
        case .graph:
            self = .graph(try container.decode(String.self, forKey: .name))
        case .default:
            self = .default
        case .named:
            self = .named
        case .all:
            self = .all
        }
    }
}
