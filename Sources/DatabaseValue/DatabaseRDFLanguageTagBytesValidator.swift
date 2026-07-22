enum DatabaseRDFLanguageTagBytesValidator {
    static func validate(
        _ bytes: UnsafeRawBufferPointer,
        range: Range<Int>
    ) -> Bool {
        guard !range.isEmpty else { return false }
        if isGrandfathered(bytes, range: range) { return true }

        var cursor = SubtagCursor(bytes: bytes, range: range)
        guard var current = cursor.next(), current.length > 0 else {
            return false
        }
        if current.isPrivateUseSingleton {
            return validatePrivateUse(cursor: &cursor)
        }

        if current.length >= 2, current.length <= 3, current.allAlpha {
            var extlangCount = 0
            current = cursor.next() ?? .end
            while current.length == 3, current.allAlpha, extlangCount < 3 {
                extlangCount += 1
                current = cursor.next() ?? .end
            }
        } else if current.length == 4, current.allAlpha {
            current = cursor.next() ?? .end
        } else if current.length >= 5,
                  current.length <= 8,
                  current.allAlpha {
            current = cursor.next() ?? .end
        } else {
            return false
        }

        if current.length == 4, current.allAlpha {
            current = cursor.next() ?? .end
        }
        if current.isRegion {
            current = cursor.next() ?? .end
        }
        let firstVariantOffset = current.range.lowerBound
        while current.isVariant {
            guard !hasPreviousVariant(
                bytes,
                firstVariantOffset: firstVariantOffset,
                candidate: current.range
            ) else {
                return false
            }
            current = cursor.next() ?? .end
        }
        var extensionSingletons: UInt64 = 0
        while current.isExtensionSingleton {
            guard let singletonIndex = current.extensionSingletonIndex else {
                return false
            }
            let singletonBit = UInt64(1) << UInt64(singletonIndex)
            guard extensionSingletons & singletonBit == 0 else {
                return false
            }
            extensionSingletons |= singletonBit
            current = cursor.next() ?? .end
            var valueCount = 0
            while current.length >= 2,
                  current.length <= 8,
                  current.allAlphanumeric {
                valueCount += 1
                current = cursor.next() ?? .end
            }
            guard valueCount > 0 else { return false }
        }
        if current.isPrivateUseSingleton {
            return validatePrivateUse(cursor: &cursor)
        }
        return current.isEnd && !cursor.isMalformed
    }

    private static func validatePrivateUse(
        cursor: inout SubtagCursor
    ) -> Bool {
        var count = 0
        while let subtag = cursor.next() {
            guard subtag.length >= 1,
                  subtag.length <= 8,
                  subtag.allAlphanumeric else {
                return false
            }
            count += 1
        }
        return count > 0 && !cursor.isMalformed
    }

    private static func hasPreviousVariant(
        _ bytes: UnsafeRawBufferPointer,
        firstVariantOffset: Int,
        candidate: Range<Int>
    ) -> Bool {
        guard candidate.lowerBound > firstVariantOffset else {
            return false
        }
        let previousEnd = candidate.lowerBound - 1
        var cursor = SubtagCursor(
            bytes: bytes,
            range: firstVariantOffset..<previousEnd
        )
        while let previous = cursor.next() {
            if asciiCaseInsensitiveEqual(
                bytes,
                lhs: previous.range,
                rhs: candidate
            ) {
                return true
            }
        }
        return false
    }

    private static func asciiCaseInsensitiveEqual(
        _ bytes: UnsafeRawBufferPointer,
        lhs: Range<Int>,
        rhs: Range<Int>
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var left = lhs.lowerBound
        var right = rhs.lowerBound
        while left < lhs.upperBound {
            guard fold(bytes[left]) == fold(bytes[right]) else {
                return false
            }
            left += 1
            right += 1
        }
        return true
    }

    private static func isGrandfathered(
        _ bytes: UnsafeRawBufferPointer,
        range: Range<Int>
    ) -> Bool {
        for tag in grandfathered {
            guard range.count == tag.utf8.count else { continue }
            var index = range.lowerBound
            var matches = true
            for byte in tag.utf8 {
                if fold(bytes[index]) != fold(byte) {
                    matches = false
                    break
                }
                index += 1
            }
            if matches { return true }
        }
        return false
    }

    private static func fold(_ byte: UInt8) -> UInt8 {
        byte >= 65 && byte <= 90 ? byte + 32 : byte
    }

    private static func isAlpha(_ byte: UInt8) -> Bool {
        let folded = fold(byte)
        return folded >= 97 && folded <= 122
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= 48 && byte <= 57
    }

    private struct SubtagCursor {
        private let bytes: UnsafeRawBufferPointer
        private let range: Range<Int>
        private var index: Int
        private var reachedEnd = false
        private(set) var isMalformed = false

        init(bytes: UnsafeRawBufferPointer, range: Range<Int>) {
            self.bytes = bytes
            self.range = range
            self.index = range.lowerBound
        }

        mutating func next() -> Subtag? {
            guard !reachedEnd else { return nil }
            guard index < range.upperBound else {
                reachedEnd = true
                return nil
            }

            let start = index
            var length = 0
            var first: UInt8 = 0
            var allAlpha = true
            var allDigit = true
            var allAlphanumeric = true

            while index < range.upperBound {
                let byte = bytes[index]
                index += 1
                if byte == 0x2D {
                    if length == 0 || index == range.upperBound {
                        isMalformed = true
                    }
                    return Subtag(
                        range: start..<(index - 1),
                        length: length,
                        first: first,
                        allAlpha: allAlpha,
                        allDigit: allDigit,
                        allAlphanumeric: allAlphanumeric
                    )
                }
                if length == 0 { first = byte }
                length += 1
                let alpha = DatabaseRDFLanguageTagBytesValidator.isAlpha(byte)
                let digit = DatabaseRDFLanguageTagBytesValidator.isDigit(byte)
                allAlpha = allAlpha && alpha
                allDigit = allDigit && digit
                allAlphanumeric = allAlphanumeric && (alpha || digit)
            }

            reachedEnd = true
            return Subtag(
                range: start..<index,
                length: length,
                first: first,
                allAlpha: allAlpha,
                allDigit: allDigit,
                allAlphanumeric: allAlphanumeric
            )
        }
    }

    private struct Subtag {
        let range: Range<Int>
        let length: Int
        let first: UInt8
        let allAlpha: Bool
        let allDigit: Bool
        let allAlphanumeric: Bool

        static let end = Self(
            range: 0..<0,
            length: 0,
            first: 0,
            allAlpha: false,
            allDigit: false,
            allAlphanumeric: false
        )

        var isEnd: Bool { length == 0 }

        var isPrivateUseSingleton: Bool {
            length == 1
                && DatabaseRDFLanguageTagBytesValidator.fold(first) == 0x78
        }

        var isExtensionSingleton: Bool {
            guard length == 1, allAlphanumeric else { return false }
            return DatabaseRDFLanguageTagBytesValidator.fold(first) != 0x78
        }

        var extensionSingletonIndex: Int? {
            guard isExtensionSingleton else { return nil }
            let value = DatabaseRDFLanguageTagBytesValidator.fold(first)
            if value >= 48, value <= 57 {
                return Int(value - 48)
            }
            guard value >= 97, value <= 122 else { return nil }
            return 10 + Int(value - 97)
        }

        var isRegion: Bool {
            (length == 2 && allAlpha) || (length == 3 && allDigit)
        }

        var isVariant: Bool {
            if length >= 5, length <= 8 {
                return allAlphanumeric
            }
            return length == 4
                && DatabaseRDFLanguageTagBytesValidator.isDigit(first)
                && allAlphanumeric
        }
    }

    private static let grandfathered = [
        "art-lojban", "cel-gaulish", "en-GB-oed", "i-ami", "i-bnn",
        "i-default", "i-enochian", "i-hak", "i-klingon", "i-lux",
        "i-mingo", "i-navajo", "i-pwn", "i-tao", "i-tay", "i-tsu",
        "no-bok", "no-nyn", "sgn-BE-FR", "sgn-BE-NL", "sgn-CH-DE",
        "zh-guoyu", "zh-hakka", "zh-min", "zh-min-nan", "zh-xiang",
    ]
}
