import DatabaseValue

enum DigestVectorFixture {
    static func bytes(repeating byte: UInt8, count: Int) -> DatabaseBytes {
        DatabaseBytes([UInt8](repeating: byte, count: count))
    }

    static func hexadecimalString(of bytes: DatabaseBytes) -> String {
        bytes.withUnsafeBytes { source in
            hexadecimalString(of: source)
        }
    }

    static func hexadecimalString(
        of source: UnsafeRawBufferPointer
    ) -> String {
        let digits: InlineArray<16, UInt8> = [
            48, 49, 50, 51, 52, 53, 54, 55,
            56, 57, 97, 98, 99, 100, 101, 102,
        ]
        return String(
            decoding: [UInt8](
                unsafeUninitializedCapacity: source.count * 2
            ) { output, initializedCount in
                for index in source.indices {
                    output[index * 2] = digits[Int(source[index] >> 4)]
                    output[index * 2 + 1] = digits[
                        Int(source[index] & 0x0f)
                    ]
                }
                initializedCount = output.count
            },
            as: UTF8.self
        )
    }

    static func forEachSegment(
        of bytes: [UInt8],
        lengths: [Int],
        _ body: (UnsafeRawBufferPointer) -> Void
    ) {
        bytes.withUnsafeBytes { source in
            var offset = 0
            for requestedLength in lengths {
                let segmentCount = min(requestedLength, source.count - offset)
                body(
                    UnsafeRawBufferPointer(
                        start: source.baseAddress?.advanced(by: offset),
                        count: segmentCount
                    )
                )
                offset += segmentCount
            }
            if offset < source.count {
                body(
                    UnsafeRawBufferPointer(
                        start: source.baseAddress!.advanced(by: offset),
                        count: source.count - offset
                    )
                )
            }
        }
    }
}
