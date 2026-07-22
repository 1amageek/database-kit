/// Immutable, owned bytes with constant-time zero-copy slicing.
public struct DatabaseBytes:
    Sendable,
    Hashable,
    RandomAccessCollection,
    ExpressibleByArrayLiteral {
    public typealias Element = UInt8
    public typealias Index = Int
    public typealias ArrayLiteralElement = UInt8

    public enum SharedStorage: Sendable {
        case array([UInt8], Range<Int>)
        case allocation(DatabaseByteAllocation, Range<Int>)
        case owner(any DatabaseByteOwner, Range<Int>)
    }

    private enum ByteStorage: Sendable {
        case array([UInt8])
        case exactArray([UInt8])
        case allocation(DatabaseByteAllocation)
        case owner(any DatabaseByteOwner)
    }

    private let storage: ByteStorage
    private let storageRange: Range<Int>

    public init(_ bytes: [UInt8]) {
        self.storage = .array(bytes)
        self.storageRange = 0..<bytes.count
    }

    public init() {
        self.storage = .exactArray([])
        self.storageRange = 0..<0
    }

    public init(allocation: DatabaseByteAllocation) {
        self.storage = .allocation(allocation)
        self.storageRange = 0..<allocation.count
    }

    /// Retains an external immutable owner without copying its bytes.
    public init(retaining owner: any DatabaseByteOwner) {
        precondition(owner.count >= 0)
        self.storage = .owner(owner)
        self.storageRange = 0..<owner.count
    }

    public init(sharing bytes: [UInt8], storageRange: Range<Int>) {
        precondition(
            storageRange.lowerBound >= bytes.startIndex
                && storageRange.upperBound <= bytes.endIndex
        )
        self.storage = .array(bytes)
        self.storageRange = storageRange
    }

    public init(
        sharing allocation: DatabaseByteAllocation,
        storageRange: Range<Int>
    ) {
        precondition(
            storageRange.lowerBound >= 0
                && storageRange.upperBound <= allocation.count
        )
        self.storage = .allocation(allocation)
        self.storageRange = storageRange
    }

    public init(arrayLiteral elements: UInt8...) {
        if elements.isEmpty {
            self.init()
        } else {
            self.init(elements)
        }
    }

    /// Allocates final storage once and initializes it through a synchronous borrow.
    public static func copying<ResultError: Error>(
        count: Int,
        _ initialize: (UnsafeMutableRawBufferPointer) throws(ResultError) -> Void
    ) throws(ResultError) -> DatabaseBytes {
        precondition(count >= 0)
        guard count > 0 else {
            return DatabaseBytes()
        }
        var initializationError: ResultError?
        let bytes = [UInt8](unsafeUninitializedCapacity: count) {
            buffer,
            initializedCount in
            do {
                try initialize(UnsafeMutableRawBufferPointer(buffer))
                initializedCount = count
            } catch let error as ResultError {
                initializationError = error
                initializedCount = 0
            } catch {
                preconditionFailure("Byte initialization threw an unexpected error type")
            }
        }
        if let initializationError {
            throw initializationError
        }
        return DatabaseBytes(exactBytes: bytes)
    }

    /// Allocates final storage once for an infallible synchronous initializer.
    public static func copying(
        count: Int,
        _ initialize: (UnsafeMutableRawBufferPointer) -> Void
    ) -> DatabaseBytes {
        precondition(count >= 0)
        guard count > 0 else {
            return DatabaseBytes()
        }
        let bytes = [UInt8](unsafeUninitializedCapacity: count) {
            buffer,
            initializedCount in
            initialize(UnsafeMutableRawBufferPointer(buffer))
            initializedCount = count
        }
        return DatabaseBytes(exactBytes: bytes)
    }

    package init(exactBytes: [UInt8]) {
        self.storage = .exactArray(exactBytes)
        self.storageRange = 0..<exactBytes.count
    }

    private init(storage: ByteStorage, storageRange: Range<Int>) {
        self.storage = storage
        self.storageRange = storageRange
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { storageRange.count }

    public var sharedStorage: SharedStorage {
        switch storage {
        case .array(let bytes), .exactArray(let bytes):
            return .array(bytes, storageRange)
        case .allocation(let allocation):
            return .allocation(allocation, storageRange)
        case .owner(let owner):
            return .owner(owner, storageRange)
        }
    }

    public subscript(position: Int) -> UInt8 {
        precondition(position >= startIndex && position < endIndex)
        return withUnsafeBytes { bytes in
            bytes[position]
        }
    }

    public func slice(_ range: Range<Int>) -> DatabaseBytes {
        precondition(range.lowerBound >= 0 && range.upperBound <= count)
        return DatabaseBytes(
            storage: storage,
            storageRange: (storageRange.lowerBound + range.lowerBound)..<(
                storageRange.lowerBound + range.upperBound
            )
        )
    }

    public func withUnsafeBytes<Result>(
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) rethrows -> Result {
        switch storage {
        case .array(let bytes), .exactArray(let bytes):
            return try bytes.withUnsafeBytes { storageBytes in
                let start = storageBytes.baseAddress?.advanced(
                    by: storageRange.lowerBound
                )
                return try body(
                    UnsafeRawBufferPointer(
                        start: start,
                        count: storageRange.count
                    )
                )
            }
        case .allocation(let allocation):
            return try allocation.withUnsafeBytes { storageBytes in
                let start = storageBytes.baseAddress?.advanced(
                    by: storageRange.lowerBound
                )
                return try body(
                    UnsafeRawBufferPointer(
                        start: start,
                        count: storageRange.count
                    )
                )
            }
        case .owner(let owner):
            var outcome: DatabaseByteBorrowOutcome<Result> = .missing
            let ownerCount = owner.count
            try owner.borrowBytes { storageBytes in
                precondition(storageBytes.count == ownerCount)
                precondition(
                    storageBytes.count == 0
                        || storageBytes.baseAddress != nil
                )
                guard case .missing = outcome else {
                    preconditionFailure(
                        "DatabaseByteOwner invoked its borrow closure more than once"
                    )
                }
                let start = storageBytes.baseAddress?.advanced(
                    by: storageRange.lowerBound
                )
                outcome = .value(
                    try body(
                        UnsafeRawBufferPointer(
                            start: start,
                            count: storageRange.count
                        )
                    )
                )
            }
            switch outcome {
            case .value(let result):
                return result
            case .missing:
                preconditionFailure(
                    "DatabaseByteOwner did not invoke its borrow closure"
                )
            }
        }
    }

    /// Exposes this value's contiguous storage to generic collection algorithms.
    ///
    /// The pointer is a synchronous borrow and must not escape `body`.
    public func withContiguousStorageIfAvailable<Result>(
        _ body: (UnsafeBufferPointer<UInt8>) throws -> Result
    ) rethrows -> Result? {
        try withUnsafeBytes { bytes in
            try body(bytes.bindMemory(to: UInt8.self))
        }
    }

    /// Materializes an independent array for APIs that require owned arrays.
    public func copyBytes() -> [UInt8] {
        withUnsafeBytes { bytes in
            Array(bytes)
        }
    }

    /// Returns exact independent storage that cannot retain a larger backing
    /// allocation or an owner with unknown retained capacity.
    public func detached() -> DatabaseBytes {
        guard !isEmpty else {
            return DatabaseBytes()
        }
        switch storage {
        case .exactArray(let bytes) where storageRange == bytes.indices:
            return self
        case .array, .exactArray, .allocation, .owner:
            break
        }
        return DatabaseBytes.copying(count: count) { destination in
            withUnsafeBytes { source in
                destination.copyMemory(from: source)
            }
        }
    }

    /// Returns contiguous array storage for array-only APIs.
    ///
    /// A full-range array-backed value shares its allocation through Array copy-on-write.
    /// Slices and adopted allocations are materialized because Array cannot represent
    /// their ownership without copying.
    public func contiguousArray() -> [UInt8] {
        switch storage {
        case .array(let bytes) where storageRange == bytes.indices:
            return bytes
        case .exactArray(let bytes) where storageRange == bytes.indices:
            return bytes
        case .array, .exactArray, .allocation, .owner:
            return copyBytes()
        }
    }

    public static func == (lhs: DatabaseBytes, rhs: DatabaseBytes) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        return lhs.withUnsafeBytes { lhsBytes in
            rhs.withUnsafeBytes { rhsBytes in
                lhsBytes.elementsEqual(rhsBytes)
            }
        }
    }

    public func lexicographicallyPrecedes(_ other: DatabaseBytes) -> Bool {
        withUnsafeBytes { lhs in
            other.withUnsafeBytes { rhs in
                let sharedCount = Swift.min(lhs.count, rhs.count)
                for offset in 0..<sharedCount {
                    if lhs[offset] != rhs[offset] {
                        return lhs[offset] < rhs[offset]
                    }
                }
                return lhs.count < rhs.count
            }
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(count)
        withUnsafeBytes { bytes in
            for byte in bytes {
                hasher.combine(byte)
            }
        }
    }
}

private enum DatabaseByteBorrowOutcome<Value> {
    case missing
    case value(Value)
}
