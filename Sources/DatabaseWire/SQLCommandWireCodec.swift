import DatabaseKit

enum SQLCommandWireCodec {
    static func tag(_ kind: SQLCommandKind) -> UInt8 {
        switch kind {
        case .begin: 0
        case .commit: 1
        case .rollback: 2
        case .set: 3
        case .show: 4
        case .reset: 5
        case .prepare: 6
        case .execute: 7
        case .deallocate: 8
        case .explain: 9
        case .copy: 10
        case .createSchema: 11
        case .alterSchema: 12
        case .dropSchema: 13
        case .createTable: 14
        case .alterTable: 15
        case .dropTable: 16
        case .createIndex: 17
        case .dropIndex: 18
        case .createView: 19
        case .dropView: 20
        case .createMaterializedView: 21
        case .refreshMaterializedView: 22
        case .dropMaterializedView: 23
        case .setConstraints: 24
        case .createSequence: 25
        case .alterSequence: 26
        case .dropSequence: 27
        case .insert: 28
        case .update: 29
        case .delete: 30
        case .merge: 31
        case .truncate: 32
        case .savepoint: 33
        case .rollbackTo: 34
        case .release: 35
        }
    }

    static func kind(_ tag: UInt8) throws(DatabaseWireError) -> SQLCommandKind {
        switch tag {
        case 0: .begin
        case 1: .commit
        case 2: .rollback
        case 3: .set
        case 4: .show
        case 5: .reset
        case 6: .prepare
        case 7: .execute
        case 8: .deallocate
        case 9: .explain
        case 10: .copy
        case 11: .createSchema
        case 12: .alterSchema
        case 13: .dropSchema
        case 14: .createTable
        case 15: .alterTable
        case 16: .dropTable
        case 17: .createIndex
        case 18: .dropIndex
        case 19: .createView
        case 20: .dropView
        case 21: .createMaterializedView
        case 22: .refreshMaterializedView
        case 23: .dropMaterializedView
        case 24: .setConstraints
        case 25: .createSequence
        case 26: .alterSequence
        case 27: .dropSequence
        case 28: .insert
        case 29: .update
        case 30: .delete
        case 31: .merge
        case 32: .truncate
        case 33: .savepoint
        case 34: .rollbackTo
        case 35: .release
        default: throw .invalidSQLResponse
        }
    }
}
