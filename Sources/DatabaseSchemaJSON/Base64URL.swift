import DatabaseTypes
import Foundation

enum Base64URL {
    static func encode(_ bytes: ByteString) -> String {
        let base64 = bytes.withUnsafeBytes { Data($0).base64EncodedString() }
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ value: String, path: String) throws -> ByteString {
        guard value.utf8.allSatisfy({
            (65...90).contains($0)
                || (97...122).contains($0)
                || (48...57).contains($0)
                || $0 == 0x2D || $0 == 0x5F
        }) else {
            throw SchemaJSONError.invalidValue(
                path: path,
                reason: "invalid base64url alphabet"
            )
        }
        let remainder = value.utf8.count % 4
        guard remainder != 1 else {
            throw SchemaJSONError.invalidValue(
                path: path,
                reason: "invalid base64url length"
            )
        }
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64) else {
            throw SchemaJSONError.invalidValue(
                path: path,
                reason: "invalid base64url value"
            )
        }
        // Foundation owns the decoded Data. The schema value receives one
        // detached owner at this external JSON boundary.
        let bytes = ByteString(Array(data))
        guard encode(bytes) == value else {
            throw SchemaJSONError.invalidValue(
                path: path,
                reason: "non-canonical base64url value"
            )
        }
        return bytes
    }
}
