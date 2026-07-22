import DatabaseValue

/// Stable, framed hashing for database values and approximate cardinality indexes.
public enum CanonicalFieldValueHash {
    public static func hash(
        _ value: FieldValue
    ) throws(DatabaseRDFTermCodecError) -> UInt64 {
        var stream = Stream()
        try append(value, to: &stream)
        return stream.finalize()
    }

    private static func append(
        _ value: FieldValue,
        to stream: inout Stream
    ) throws(DatabaseRDFTermCodecError) {
        switch value {
        case .null:
            stream.update(byte: 0x00)
        case .bool(let value):
            stream.update(byte: 0x01)
            stream.update(byte: value ? 1 : 0)
        case .int64(let value):
            stream.update(byte: 0x02)
            stream.updateLittleEndian(value)
        case .uint64(let value):
            appendUnsignedInteger(value, to: &stream)
        case .double(let value):
            if let exactInteger = Int64(exactly: value) {
                stream.update(byte: 0x02)
                stream.updateLittleEndian(exactInteger)
            } else if let exactInteger = UInt64(exactly: value) {
                appendUnsignedInteger(exactInteger, to: &stream)
            } else {
                stream.update(byte: 0x03)
                let bits = value == 0 ? UInt64(0) : value.bitPattern
                stream.updateLittleEndian(bits)
            }
        case .string(let value):
            stream.update(byte: 0x04)
            stream.updateLittleEndian(UInt64(value.utf8.count))
            stream.update(value.utf8)
        case .data(let value):
            stream.update(byte: 0x05)
            stream.updateLittleEndian(UInt64(value.count))
            value.withUnsafeBytes { bytes in
                stream.update(bytes)
            }
        case .rdfTerm(let term):
            stream.update(byte: 0x06)
            let plan = try DatabaseRDFTermCodec.encodingPlan(term)
            stream.updateLittleEndian(UInt64(plan.byteCount))
            var sink = RDFSink(stream: stream)
            try DatabaseRDFTermCodec.encode(plan, into: &sink)
            stream = sink.stream
        case .array(let values):
            stream.update(byte: 0x07)
            stream.updateLittleEndian(UInt64(values.count))
            for value in values {
                try append(value, to: &stream)
            }
        }
    }

    private static func appendUnsignedInteger(
        _ value: UInt64,
        to stream: inout Stream
    ) {
        if value <= UInt64(Int64.max) {
            stream.update(byte: 0x02)
            stream.updateLittleEndian(Int64(value))
        } else {
            stream.update(byte: 0x08)
            stream.updateLittleEndian(value)
        }
    }

    private struct RDFSink: DatabaseRDFTermEncodingSink {
        var stream: Stream

        mutating func write(_ byte: UInt8) {
            stream.update(byte: byte)
        }

        mutating func write(_ bytes: UnsafeRawBufferPointer) {
            stream.update(bytes)
        }
    }

    private struct Stream {
        private var h1: UInt64 = 0
        private var h2: UInt64 = 0
        private var tailLow: UInt64 = 0
        private var tailHigh: UInt64 = 0
        private var tailCount = 0
        private var byteCount = 0

        private static let c1: UInt64 = 0x87c3_7b91_1142_53d5
        private static let c2: UInt64 = 0x4cf5_ad43_2745_937f

        mutating func update<Bytes: Sequence>(_ bytes: Bytes)
        where Bytes.Element == UInt8 {
            for byte in bytes {
                update(byte: byte)
            }
        }

        mutating func update(byte: UInt8) {
            if tailCount < 8 {
                tailLow |= UInt64(byte) << UInt64(tailCount * 8)
            } else {
                tailHigh |= UInt64(byte) << UInt64((tailCount - 8) * 8)
            }
            tailCount += 1
            byteCount += 1
            if tailCount == 16 {
                mixBlock(low: tailLow, high: tailHigh)
                tailLow = 0
                tailHigh = 0
                tailCount = 0
            }
        }

        mutating func updateLittleEndian<Integer: FixedWidthInteger>(
            _ value: Integer
        ) {
            var remaining = Integer.Magnitude(truncatingIfNeeded: value)
            for _ in 0..<MemoryLayout<Integer>.size {
                update(byte: UInt8(truncatingIfNeeded: remaining))
                remaining >>= 8
            }
        }

        func finalize() -> UInt64 {
            var finalizedH1 = h1
            var finalizedH2 = h2
            if tailCount > 8 {
                var k2 = tailHigh
                k2 = k2 &* Self.c2
                k2 = Self.rotateLeft(k2, by: 33)
                k2 = k2 &* Self.c1
                finalizedH2 ^= k2
            }
            if tailCount > 0 {
                var k1 = tailLow
                k1 = k1 &* Self.c1
                k1 = Self.rotateLeft(k1, by: 31)
                k1 = k1 &* Self.c2
                finalizedH1 ^= k1
            }
            finalizedH1 ^= UInt64(byteCount)
            finalizedH2 ^= UInt64(byteCount)
            finalizedH1 = finalizedH1 &+ finalizedH2
            finalizedH2 = finalizedH2 &+ finalizedH1
            finalizedH1 = Self.finalMix(finalizedH1)
            finalizedH2 = Self.finalMix(finalizedH2)
            return finalizedH1 &+ finalizedH2
        }

        private mutating func mixBlock(low: UInt64, high: UInt64) {
            var k1 = low
            var k2 = high
            k1 = k1 &* Self.c1
            k1 = Self.rotateLeft(k1, by: 31)
            k1 = k1 &* Self.c2
            h1 ^= k1
            h1 = Self.rotateLeft(h1, by: 27)
            h1 = h1 &+ h2
            h1 = h1 &* 5 &+ 0x52dc_e729
            k2 = k2 &* Self.c2
            k2 = Self.rotateLeft(k2, by: 33)
            k2 = k2 &* Self.c1
            h2 ^= k2
            h2 = Self.rotateLeft(h2, by: 31)
            h2 = h2 &+ h1
            h2 = h2 &* 5 &+ 0x3849_5ab5
        }

        private static func rotateLeft(_ value: UInt64, by count: Int) -> UInt64 {
            (value << count) | (value >> (64 - count))
        }

        private static func finalMix(_ value: UInt64) -> UInt64 {
            var result = value
            result ^= result >> 33
            result = result &* 0xff51_afd7_ed55_8ccd
            result ^= result >> 33
            result = result &* 0xc4ce_b9fe_1a85_ec53
            result ^= result >> 33
            return result
        }
    }
}

public extension FieldValue {
    func stableHash() throws(DatabaseRDFTermCodecError) -> UInt64 {
        try CanonicalFieldValueHash.hash(self)
    }
}
