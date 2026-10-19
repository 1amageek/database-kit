import DatabaseKit
import DatabaseTypes

public extension RemoteOperationError {
    /// Adds typed SQL metadata without changing the generic failure envelope.
    init(category: OperationErrorCategory, code: String, message: String,
         retryability: OperationRetryability, details: FieldObject = FieldObject(),
         sqlDiagnostic: SQLDiagnostic) throws(DatabaseWireError) {
        guard details["sqlDiagnostic"] == nil else { throw .invalidSQLDiagnostic }
        let diagnostic = try SQLDiagnosticWireCodec.object(sqlDiagnostic)
        var fields = details.fields
        fields.append(("sqlDiagnostic", .object(diagnostic)))
        let merged: FieldObject
        do { merged = try FieldObject(fields) }
        catch { throw .invalidFieldObject(error) }
        self.init(category: category, code: code, message: message,
                  retryability: retryability, details: merged)
    }

    /// Nil means absent metadata; malformed reserved metadata is always a failure.
    func sqlDiagnostic() throws(DatabaseWireError) -> SQLDiagnostic? {
        guard let value = details["sqlDiagnostic"] else { return nil }
        guard case .object(let object) = value else { throw .invalidSQLDiagnostic }
        return try SQLDiagnosticWireCodec.diagnostic(object)
    }
}
