import DatabaseWire

/// Strict, human-readable JSON adaptation for the canonical schema manifest.
///
/// The JSON document is a one-to-one representation of `Schema`. Its
/// fingerprint remains the digest of `SchemaManifest.canonicalBytes`, not the
/// textual JSON spelling or member order.
public struct SchemaJSONCodec: Sendable {
    public let limits: DatabaseWireLimits

    public init(limits: DatabaseWireLimits = .default) {
        self.limits = limits
    }

    public func encode(
        _ manifest: SchemaManifest
    ) throws(SchemaJSONError) -> String {
        do {
            let output = JSONWriter.encode(try encodeManifest(manifest))
            let count = output.utf8.count
            guard count <= limits.maximumFrameBytes else {
                throw SchemaJSONError.outputTooLarge(
                    actual: count,
                    maximum: limits.maximumFrameBytes
                )
            }
            return output
        } catch let error as SchemaJSONError {
            throw error
        } catch {
            throw .invalidValue(path: "schema", reason: String(describing: error))
        }
    }

    public func decode(
        _ text: String
    ) throws(SchemaJSONError) -> SchemaManifest {
        do {
            let root = try JSONParser(
                maximumBytes: limits.maximumFrameBytes,
                maximumDepth: limits.maximumNestingDepth,
                maximumCollectionCount: limits.maximumCollectionCount
            ).parse(text)
            return try decodeManifest(root)
        } catch let error as SchemaJSONError {
            throw error
        } catch {
            throw .invalidSchema(reason: String(describing: error))
        }
    }

    var fieldValueCodec: FieldValueJSONCodec {
        FieldValueJSONCodec(
            maximumBytes: limits.maximumFrameBytes,
            maximumDepth: limits.maximumNestingDepth,
            maximumCollectionCount: limits.maximumCollectionCount
        )
    }
}
