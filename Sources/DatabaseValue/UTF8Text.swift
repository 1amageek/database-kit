/// Deterministic string operations used by the platform-neutral database core.
package enum UTF8Text {
    /// Returns whether `pattern` occurs as the same UTF-8 byte sequence.
    public static func contains(_ pattern: String, in value: String) -> Bool {
        firstRange(of: pattern, in: value) != nil
    }

    /// Searches a borrowed view without materializing it as an owned string.
    public static func contains(_ pattern: String, in value: Substring) -> Bool {
        firstRange(of: pattern, in: value) != nil
    }

    /// Returns indices that are valid only for `value` and its shared storage.
    public static func firstRange(
        of pattern: String,
        in value: String
    ) -> Range<String.Index>? {
        firstRange(of: pattern, in: value[value.startIndex...])
    }

    public static func firstRange(
        of pattern: String,
        in value: Substring
    ) -> Range<String.Index>? {
        guard !pattern.isEmpty else {
            return value.startIndex..<value.startIndex
        }

        let patternBytes = pattern.utf8
        let valueBytes = value.utf8
        var candidate = valueBytes.startIndex
        while candidate < valueBytes.endIndex {
            var sourceIndex = candidate
            var patternIndex = patternBytes.startIndex
            while sourceIndex < valueBytes.endIndex,
                  patternIndex < patternBytes.endIndex,
                  valueBytes[sourceIndex] == patternBytes[patternIndex] {
                sourceIndex = valueBytes.index(after: sourceIndex)
                patternIndex = patternBytes.index(after: patternIndex)
            }
            if patternIndex == patternBytes.endIndex {
                return candidate..<sourceIndex
            }
            candidate = valueBytes.index(after: candidate)
        }
        return nil
    }

    public static func replacingOccurrences(
        in value: String,
        of pattern: String,
        with replacement: String
    ) -> String {
        precondition(!pattern.isEmpty, "Replacement pattern must not be empty")
        let sourceByteCount = value.utf8.count
        let byteGrowthPerMatch = replacement.utf8.count - pattern.utf8.count
        let outputCapacity: Int
        if byteGrowthPerMatch > 0 {
            let matchCount = occurrenceCount(of: pattern, in: value)
            let (growth, growthOverflow) = byteGrowthPerMatch
                .multipliedReportingOverflow(by: matchCount)
            let (capacity, capacityOverflow) = sourceByteCount
                .addingReportingOverflow(growth)
            precondition(
                !growthOverflow && !capacityOverflow,
                "Replacement output exceeds the supported string size"
            )
            outputCapacity = capacity
        } else {
            outputCapacity = sourceByteCount
        }

        var result = ""
        result.reserveCapacity(outputCapacity)
        var unmatchedStart = value.startIndex
        var search = value[value.startIndex...]
        while let range = firstRange(of: pattern, in: search) {
            result.append(contentsOf: value[unmatchedStart..<range.lowerBound])
            result.append(replacement)
            unmatchedStart = range.upperBound
            search = value[range.upperBound...]
        }
        result.append(contentsOf: value[unmatchedStart...])
        return result
    }

    private static func occurrenceCount(
        of pattern: String,
        in value: String
    ) -> Int {
        var count = 0
        var search = value[value.startIndex...]
        while let range = firstRange(of: pattern, in: search) {
            count += 1
            search = value[range.upperBound...]
        }
        return count
    }

    public static func isEqualIgnoringASCIICase(
        _ left: String,
        _ right: String
    ) -> Bool {
        let leftBytes = left.utf8
        let rightBytes = right.utf8
        guard leftBytes.count == rightBytes.count else {
            return false
        }
        return leftBytes.elementsEqual(rightBytes) {
            asciiLowercased($0) == asciiLowercased($1)
        }
    }

    public static func trimmingWhitespace(_ value: String) -> Substring {
        var lowerBound = value.startIndex
        var upperBound = value.endIndex
        while lowerBound < upperBound, value[lowerBound].isWhitespace {
            lowerBound = value.index(after: lowerBound)
        }
        while lowerBound < upperBound {
            let previous = value.index(before: upperBound)
            guard value[previous].isWhitespace else {
                break
            }
            upperBound = previous
        }
        return value[lowerBound..<upperBound]
    }

    private static func asciiLowercased(_ byte: UInt8) -> UInt8 {
        byte >= 65 && byte <= 90 ? byte + 32 : byte
    }
}
