import DatabaseTypes

/// All borrowed input is consumed synchronously; no pointer escapes parsing.
struct QueryJSONParser {
    let input: UnsafeRawBufferPointer
    let limits: QueryValueLimits
    let buildsTree: Bool
    var offset = 0
    var nodes: UInt64 = 0
    var elements: UInt64 = 0
    var decodedBytes: UInt64 = 0
    var maximumDepth: UInt64 = 0
    var frames: [Frame] = []
    var rootID: Int?
    var builder: QueryJSONBBuilder

    init(input: UnsafeRawBufferPointer, limits: QueryValueLimits, buildsTree: Bool) {
        self.input = input
        self.limits = limits
        self.buildsTree = buildsTree
        self.builder = QueryJSONBBuilder(limits: limits)
    }

    struct Frame {
        let isObject: Bool
        var state = 0
        var key = ""
        var values: [Int] = []
        var members: [(member: QueryJSONBIndexedMember, ordinal: Int)] = []
    }

    static func validate(bytes: ByteString, limits: QueryValueLimits) throws(QueryValueError) -> QueryValueFootprint {
        try parse(bytes: bytes, limits: limits, buildsTree: false).footprint
    }

    static func decode(bytes: ByteString, limits: QueryValueLimits) throws(QueryValueError) -> QueryJSONBNode {
        try parse(bytes: bytes, limits: limits, buildsTree: true).root
    }

    private static func parse(
        bytes: ByteString, limits: QueryValueLimits, buildsTree: Bool
    ) throws(QueryValueError) -> (root: QueryJSONBNode, footprint: QueryValueFootprint) {
        // Unknown retained ownership cannot be admitted as the visible slice size.
        guard let retained = bytes.retainedByteCount else {
            throw .unknownRetainedByteCount
        }
        try check(UInt64(retained), maximum: limits.maximumRetainedBytes, resource: "retainedBytes")
        return try bytes.withUnsafeBytes { input in
            Result<(root: QueryJSONBNode, footprint: QueryValueFootprint), QueryValueError> { () throws(QueryValueError) in
                var parser = Self(input: input, limits: limits, buildsTree: buildsTree)
                try parser.validateUTF8()
                let root = try parser.parseDocument()
                return (root, QueryValueFootprint(nodeCount: parser.nodes, collectionElementCount: parser.elements, retainedByteCount: UInt64(retained), maximumNestingDepth: parser.maximumDepth))
            }
        }.get()
    }

    static func check(_ actual: UInt64, maximum: UInt64, resource: String) throws(QueryValueError) {
        guard actual <= maximum else {
            throw .resourceLimit(resource: resource, actual: actual, maximum: maximum)
        }
    }

    mutating func parseDocument() throws(QueryValueError) -> QueryJSONBNode {
        while true {
            skipWhitespace()
            if frames.isEmpty {
                if let rootID {
                    guard offset == input.count else { throw invalid("Trailing input") }
                    guard buildsTree else { return .null }
                    let completedBuilder = builder
                    return try completedBuilder.finish(root: rootID)
                }
                try readValue()
                continue
            }
            let index = frames.count - 1
            let isObject = frames[index].isObject
            let state = frames[index].state
            if isObject {
                switch state {
                case 0, 4:
                    if state == 0, consume(125) { try closeCollection(); continue }
                    try admitElement()
                    guard peek == 34 else { throw invalid("Expected object key") }
                    frames[index].key = try readString()
                    frames[index].state = 1
                case 1:
                    guard consume(58) else { throw invalid("Expected colon") }
                    frames[index].state = 2
                case 2: try readValue()
                default:
                    if consume(125) { try closeCollection() }
                    else if consume(44) { frames[index].state = 4 }
                    else { throw invalid("Expected comma or object end") }
                }
            } else {
                switch state {
                case 0, 2:
                    if state == 0, consume(93) { try closeCollection(); continue }
                    try admitElement()
                    try readValue()
                default:
                    if consume(93) { try closeCollection() }
                    else if consume(44) { frames[index].state = 2 }
                    else { throw invalid("Expected comma or array end") }
                }
            }
        }
    }

    mutating func admitElement() throws(QueryValueError) {
        let next = elements.addingReportingOverflow(1)
        guard !next.overflow else { throw .arithmeticOverflow }
        try Self.check(next.partialValue, maximum: limits.maximumCollectionElements, resource: "collectionElements")
        elements = next.partialValue
    }

    mutating func readValue() throws(QueryValueError) {
        let next = nodes.addingReportingOverflow(1)
        guard !next.overflow else { throw .arithmeticOverflow }
        try Self.check(next.partialValue, maximum: limits.maximumTotalNodes, resource: "nodes")
        try Self.check(UInt64(frames.count) + 1, maximum: limits.maximumNestingDepth, resource: "depth")
        nodes = next.partialValue
        maximumDepth = max(maximumDepth, UInt64(frames.count) + 1)
        guard let token = peek else { throw invalid("Expected JSON value") }
        switch token {
        case 123, 91:
            let isObject = token == 123
            offset += 1
            frames.append(Frame(isObject: isObject))
        case 34: try attach(.string(try readString()))
        case 110: try readKeyword([110, 117, 108, 108]); try attach(.null)
        case 116: try readKeyword([116, 114, 117, 101]); try attach(.bool(true))
        case 102: try readKeyword([102, 97, 108, 115, 101]); try attach(.bool(false))
        case 45, 48...57:
            let number = try readNumber()
            try attach(number.map(QueryJSONBNode.number) ?? .null)
        default: throw invalid("Expected JSON value")
        }
    }

    mutating func attach(_ node: QueryJSONBNode) throws(QueryValueError) {
        let id = buildsTree ? try builder.append(node) : -1
        attachID(id)
    }

    mutating func attachID(_ id: Int) {
        guard !frames.isEmpty else { rootID = id; return }
        let index = frames.count - 1
        if frames[index].isObject {
            if buildsTree {
                let member = QueryJSONBIndexedMember(key: frames[index].key, value: id)
                frames[index].members.append((member, frames[index].members.count))
            }
            frames[index].state = 3
        } else {
            if buildsTree { frames[index].values.append(id) }
            frames[index].state = 1
        }
    }

    mutating func closeCollection() throws(QueryValueError) {
        var frame = frames.removeLast()
        guard buildsTree else { attachID(-1); return }
        let id: Int
        if frame.isObject {
            frame.members.sort {
                let order = Self.compareKeys($0.member.key, $1.member.key)
                return order == 0 ? $0.ordinal < $1.ordinal : order < 0
            }
            var members: [QueryJSONBIndexedMember] = []
            for entry in frame.members {
                if let last = members.last, Self.compareKeys(last.key, entry.member.key) == 0 {
                    members[members.count - 1] = entry.member
                } else {
                    members.append(entry.member)
                }
            }
            id = try builder.appendObject(members)
        } else {
            id = try builder.appendArray(frame.values)
        }
        attachID(id)
    }

    static func compareKeys(_ left: String, _ right: String) -> Int {
        let lhs = left.utf8, rhs = right.utf8
        if lhs.count != rhs.count { return lhs.count < rhs.count ? -1 : 1 }
        for (a, b) in zip(lhs, rhs) where a != b { return a < b ? -1 : 1 }
        return 0
    }

    var peek: UInt8? { offset < input.count ? input[offset] : nil }

    mutating func consume(_ byte: UInt8) -> Bool {
        guard peek == byte else { return false }
        offset += 1
        return true
    }

    mutating func skipWhitespace() {
        while let byte = peek, byte == 32 || byte == 9 || byte == 10 || byte == 13 { offset += 1 }
    }

    func invalid(_ reason: String) -> QueryValueError {
        .invalidJSON(offset: UInt64(offset), reason: reason)
    }

    mutating func readKeyword(_ expected: [UInt8]) throws(QueryValueError) {
        for byte in expected {
            guard consume(byte) else { throw invalid("Invalid JSON keyword") }
        }
    }

    func validateUTF8() throws(QueryValueError) {
        var index = 0
        while index < input.count {
            let first = input[index]
            if first < 128 { index += 1; continue }
            let count: Int
            let minimumSecond: UInt8
            let maximumSecond: UInt8
            switch first {
            case 0xC2...0xDF: count = 2; minimumSecond = 0x80; maximumSecond = 0xBF
            case 0xE0: count = 3; minimumSecond = 0xA0; maximumSecond = 0xBF
            case 0xE1...0xEC, 0xEE...0xEF: count = 3; minimumSecond = 0x80; maximumSecond = 0xBF
            case 0xED: count = 3; minimumSecond = 0x80; maximumSecond = 0x9F
            case 0xF0: count = 4; minimumSecond = 0x90; maximumSecond = 0xBF
            case 0xF1...0xF3: count = 4; minimumSecond = 0x80; maximumSecond = 0xBF
            case 0xF4: count = 4; minimumSecond = 0x80; maximumSecond = 0x8F
            default: throw .invalidUTF8(offset: UInt64(index))
            }
            guard input.count - index >= count,
                  input[index + 1] >= minimumSecond,
                  input[index + 1] <= maximumSecond else {
                throw .invalidUTF8(offset: UInt64(index))
            }
            for continuation in 2..<count {
                guard (0x80...0xBF).contains(input[index + continuation]) else {
                    throw .invalidUTF8(offset: UInt64(index + continuation))
                }
            }
            index += count
        }
    }
}
