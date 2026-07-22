enum DatabaseRDFIRIParser {
    static func validate(_ value: String) throws(DatabaseRDFIRIError) {
        let bytes = value.utf8
        guard let colon = bytes.firstIndex(of: 0x3A) else {
            throw .missingScheme
        }
        try validateScheme(value[..<colon])

        let hierarchyStart = bytes.index(after: colon)
        let fragmentStart = bytes[hierarchyStart...].firstIndex(of: 0x23)
        let beforeFragmentEnd = fragmentStart ?? value.endIndex
        if let fragmentStart {
            let fragment = value[bytes.index(after: fragmentStart)...]
            try validateCharacters(fragment, component: .fragment, in: value)
        }

        let queryStart = bytes[hierarchyStart..<beforeFragmentEnd]
            .firstIndex(of: 0x3F)
        let hierarchyEnd = queryStart ?? beforeFragmentEnd
        if let queryStart {
            let query = value[bytes.index(after: queryStart)..<beforeFragmentEnd]
            try validateCharacters(query, component: .query, in: value)
        }

        let hierarchy = value[hierarchyStart..<hierarchyEnd]
        if hasDoubleSlashPrefix(hierarchy) {
            let hierarchyBytes = hierarchy.utf8
            let authorityStart = hierarchyBytes.index(
                hierarchyBytes.startIndex,
                offsetBy: 2
            )
            let authorityEnd = hierarchyBytes[authorityStart...]
                .firstIndex(of: 0x2F) ?? hierarchy.endIndex
            try validateAuthority(
                hierarchy[authorityStart..<authorityEnd],
                in: value
            )
            try validatePath(hierarchy[authorityEnd...], in: value)
        } else {
            try validatePath(hierarchy, in: value)
        }
    }

    private static func validateScheme(
        _ scheme: Substring
    ) throws(DatabaseRDFIRIError) {
        guard let first = scheme.utf8.first else {
            throw .missingScheme
        }
        guard isASCIIAlpha(first) else {
            throw .invalidScheme(byteOffset: 0)
        }
        var offset = 1
        for byte in scheme.utf8.dropFirst() {
            guard isASCIIAlpha(byte) || isASCIIDigit(byte)
                    || byte == 43 || byte == 45 || byte == 46 else {
                throw .invalidScheme(byteOffset: offset)
            }
            offset += 1
        }
    }

    private static func validateAuthority(
        _ authority: Substring,
        in source: String
    ) throws(DatabaseRDFIRIError) {
        let authorityBytes = authority.utf8
        let at = authorityBytes.lastIndex(of: 0x40)
        let hostPortStart: Substring.Index
        if let at {
            try validateCharacters(
                authority[..<at],
                component: .userinfo,
                in: source
            )
            hostPortStart = authorityBytes.index(after: at)
        } else {
            hostPortStart = authority.startIndex
        }
        let hostPort = authority[hostPortStart...]

        let hostPortBytes = hostPort.utf8
        if hostPortBytes.first == 0x5B {
            guard let closingBracket = hostPortBytes.firstIndex(of: 0x5D) else {
                throw .invalidAuthority
            }
            let literalStart = hostPortBytes.index(after: hostPort.startIndex)
            guard literalStart < closingBracket else {
                throw .invalidIPLiteral
            }
            try validateIPLiteral(hostPort[literalStart..<closingBracket])
            let suffixStart = hostPortBytes.index(after: closingBracket)
            let suffix = hostPort[suffixStart...]
            if !suffix.isEmpty {
                let suffixBytes = suffix.utf8
                guard suffixBytes.first == 0x3A else {
                    throw .invalidAuthority
                }
                try validatePort(
                    suffix[suffixBytes.index(after: suffixBytes.startIndex)...]
                )
            }
            return
        }

        let portSeparator = hostPortBytes.lastIndex(of: 0x3A)
        let hostEnd = portSeparator ?? hostPort.endIndex
        try validateCharacters(
            hostPort[..<hostEnd],
            component: .registeredName,
            in: source
        )
        if let portSeparator {
            try validatePort(
                hostPort[hostPortBytes.index(after: portSeparator)...]
            )
        }
    }

    private static func validatePort(
        _ port: Substring
    ) throws(DatabaseRDFIRIError) {
        guard port.utf8.allSatisfy(isASCIIDigit) else {
            throw .invalidAuthority
        }
    }

    private static func validatePath(
        _ path: Substring,
        in source: String
    ) throws(DatabaseRDFIRIError) {
        try validateCharacters(path, component: .path, in: source)
    }

    private static func hasDoubleSlashPrefix(_ value: Substring) -> Bool {
        let bytes = value.utf8
        guard bytes.first == 0x2F else { return false }
        let second = bytes.index(after: bytes.startIndex)
        return second != bytes.endIndex && bytes[second] == 0x2F
    }

    private static func validateCharacters(
        _ value: Substring,
        component: Component,
        in source: String
    ) throws(DatabaseRDFIRIError) {
        let scalars = value.unicodeScalars
        var index = scalars.startIndex
        while index != scalars.endIndex {
            let scalar = scalars[index]
            if isForbiddenBidirectionalFormattingCharacter(scalar.value) {
                throw .forbiddenBidirectionalFormattingCharacter(
                    scalar: scalar.value,
                    byteOffset: byteOffset(of: index, in: source)
                )
            }
            if scalar.value == 0x25 {
                let percentOffset = byteOffset(of: index, in: source)
                scalars.formIndex(after: &index)
                guard index != scalars.endIndex,
                      isASCIIHex(scalars[index].value) else {
                    throw .invalidPercentEncoding(byteOffset: percentOffset)
                }
                scalars.formIndex(after: &index)
                guard index != scalars.endIndex,
                      isASCIIHex(scalars[index].value) else {
                    throw .invalidPercentEncoding(byteOffset: percentOffset)
                }
                scalars.formIndex(after: &index)
                continue
            }
            guard component.permits(scalar) else {
                throw .invalidCharacter(
                    byteOffset: byteOffset(of: index, in: source)
                )
            }
            scalars.formIndex(after: &index)
        }
    }

    private static func validateIPLiteral(
        _ literal: Substring
    ) throws(DatabaseRDFIRIError) {
        if let first = literal.utf8.first, first == 86 || first == 118 {
            guard validateIPvFuture(literal) else {
                throw .invalidIPLiteral
            }
            return
        }
        guard validateIPv6(literal) else {
            throw .invalidIPLiteral
        }
    }

    private static func validateIPvFuture(_ literal: Substring) -> Bool {
        let bytes = literal.utf8
        var index = bytes.index(after: bytes.startIndex)
        var hexCount = 0
        while index != bytes.endIndex, isASCIIHex(bytes[index]) {
            hexCount += 1
            bytes.formIndex(after: &index)
        }
        guard hexCount > 0, index != bytes.endIndex, bytes[index] == 46 else {
            return false
        }
        bytes.formIndex(after: &index)
        var valueCount = 0
        while index != bytes.endIndex {
            let byte = bytes[index]
            guard isASCIIUnreserved(byte) || isSubDelimiter(byte)
                    || byte == 58 else {
                return false
            }
            valueCount += 1
            bytes.formIndex(after: &index)
        }
        return valueCount > 0
    }

    private static func validateIPv6(_ address: Substring) -> Bool {
        guard address.utf8.allSatisfy({
            isASCIIHex($0) || $0 == 58 || $0 == 46
        }) else {
            return false
        }

        var compression: (first: Substring.Index, after: Substring.Index)?
        var index = address.startIndex
        var previousColon: Substring.Index?
        while index != address.endIndex {
            if address[index] == ":" {
                if let previousColon,
                   address.index(after: previousColon) == index {
                    guard compression == nil else { return false }
                    compression = (previousColon, address.index(after: index))
                }
                previousColon = index
            } else {
                previousColon = nil
            }
            address.formIndex(after: &index)
        }

        if let compression {
            guard let left = ipv6UnitCount(address[..<compression.first]),
                  let right = ipv6UnitCount(address[compression.after...]),
                  left + right < 8 else {
                return false
            }
            return true
        }

        return ipv6UnitCount(address) == 8
    }

    private static func ipv6UnitCount(_ value: Substring) -> Int? {
        if value.isEmpty { return 0 }
        var count = 0
        var segmentStart = value.startIndex
        while true {
            let separator = value[segmentStart...].firstIndex(of: ":")
            let segmentEnd = separator ?? value.endIndex
            let segment = value[segmentStart..<segmentEnd]
            guard !segment.isEmpty else { return nil }
            if segment.contains(".") {
                guard separator == nil, validateIPv4(segment) else { return nil }
                count += 2
            } else {
                guard segment.utf8.count <= 4,
                      segment.utf8.allSatisfy(isASCIIHex) else {
                    return nil
                }
                count += 1
            }
            guard count <= 8 else { return nil }
            guard let separator else { return count }
            segmentStart = value.index(after: separator)
        }
    }

    private static func validateIPv4(_ address: Substring) -> Bool {
        var componentCount = 0
        var componentStart = address.startIndex
        while true {
            let separator = address[componentStart...].firstIndex(of: ".")
            let componentEnd = separator ?? address.endIndex
            let component = address[componentStart..<componentEnd]
            guard !component.isEmpty, component.utf8.count <= 3,
                  component.utf8.allSatisfy(isASCIIDigit),
                  component.utf8.count == 1 || component.utf8.first != 48 else {
                return false
            }
            var number = 0
            for byte in component.utf8 {
                number = number * 10 + Int(byte - 48)
            }
            guard number <= 255 else { return false }
            componentCount += 1
            guard let separator else { return componentCount == 4 }
            componentStart = address.index(after: separator)
        }
    }

    private static func byteOffset(
        of index: String.Index,
        in source: String
    ) -> Int {
        let utf8 = source.utf8
        guard let utf8Index = index.samePosition(in: utf8) else {
            return utf8.count
        }
        return utf8.distance(from: utf8.startIndex, to: utf8Index)
    }

    private enum Component {
        case userinfo
        case registeredName
        case path
        case query
        case fragment

        func permits(_ scalar: Unicode.Scalar) -> Bool {
            if DatabaseRDFIRIParser.isIUnreserved(scalar)
                || DatabaseRDFIRIParser.isSubDelimiter(scalar.value) {
                return true
            }
            switch self {
            case .userinfo:
                return scalar.value == 0x3A
            case .registeredName:
                return false
            case .path:
                return scalar.value == 0x3A || scalar.value == 0x40
                    || scalar.value == 0x2F
            case .query:
                return scalar.value == 0x3A || scalar.value == 0x40
                    || scalar.value == 0x2F || scalar.value == 0x3F
                    || DatabaseRDFIRIParser.isIPrivate(scalar.value)
            case .fragment:
                return scalar.value == 0x3A || scalar.value == 0x40
                    || scalar.value == 0x2F || scalar.value == 0x3F
            }
        }
    }

    private static func isIUnreserved(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if value <= 0x7F {
            return isASCIIUnreserved(UInt8(value))
        }
        switch value {
        case 0xA0...0xD7FF, 0xF900...0xFDCF, 0xFDF0...0xFFEF,
             0x10000...0x1FFFD, 0x20000...0x2FFFD,
             0x30000...0x3FFFD, 0x40000...0x4FFFD,
             0x50000...0x5FFFD, 0x60000...0x6FFFD,
             0x70000...0x7FFFD, 0x80000...0x8FFFD,
             0x90000...0x9FFFD, 0xA0000...0xAFFFD,
             0xB0000...0xBFFFD, 0xC0000...0xCFFFD,
             0xD0000...0xDFFFD, 0xE1000...0xEFFFD:
            return true
        default:
            return false
        }
    }

    private static func isIPrivate(_ value: UInt32) -> Bool {
        switch value {
        case 0xE000...0xF8FF, 0xF0000...0xFFFFD,
             0x100000...0x10FFFD:
            return true
        default:
            return false
        }
    }

    private static func isForbiddenBidirectionalFormattingCharacter(
        _ value: UInt32
    ) -> Bool {
        value == 0x200E || value == 0x200F
            || (value >= 0x202A && value <= 0x202E)
    }

    private static func isASCIIUnreserved(_ byte: UInt8) -> Bool {
        isASCIIAlpha(byte) || isASCIIDigit(byte)
            || byte == 45 || byte == 46 || byte == 95 || byte == 126
    }

    private static func isSubDelimiter(_ value: UInt32) -> Bool {
        guard value <= 0x7F else { return false }
        return isSubDelimiter(UInt8(value))
    }

    private static func isSubDelimiter(_ byte: UInt8) -> Bool {
        switch byte {
        case 33, 36, 38, 39, 40, 41, 42, 43, 44, 59, 61:
            return true
        default:
            return false
        }
    }

    private static func isASCIIAlpha(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        byte >= 48 && byte <= 57
    }

    private static func isASCIIHex(_ byte: UInt8) -> Bool {
        isASCIIDigit(byte) || (byte >= 65 && byte <= 70)
            || (byte >= 97 && byte <= 102)
    }

    private static func isASCIIHex(_ value: UInt32) -> Bool {
        value <= 0x7F && isASCIIHex(UInt8(value))
    }
}
