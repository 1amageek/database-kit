/// SQLEscape.swift
/// SQL and SPARQL identifier and string escaping utilities
///
/// Reference:
/// - ISO/IEC 9075:2023 (SQL identifier quoting)
/// - W3C SPARQL 1.1 (NCName validation)
/// - W3C XML Namespaces (NCName production)


// MARK: - SQL Escaping

/// SQL identifier and string escaping utilities
public enum SQLEscape {
    /// Quote SQL identifier (table/column names)
    /// Uses double-quote escaping per SQL standard
    ///
    /// Reference: ISO/IEC 9075:2023 Section 5.2 <delimited identifier>
    public static func identifier(_ name: String) -> String {
        "\"\(escape(name, character: "\"", replacement: "\"\""))\""
    }

    /// Escape SQL string literal
    /// Uses single-quote escaping per SQL standard
    ///
    /// Reference: ISO/IEC 9075:2023 Section 5.3 <character string literal>
    public static func string(_ value: String) -> String {
        "'\(escape(value, character: "'", replacement: "''"))'"
    }

    /// Quote identifier only if it contains special characters
    /// Returns unquoted if it's a simple identifier (letters, digits, underscore)
    public static func identifierIfNeeded(_ name: String) -> String {
        // SQL standard simple identifier: starts with letter, contains only letters, digits, underscore
        if isUnquotedIdentifier(name) {
            // Also check against reserved words
            if !sqlReservedWords.contains(name.uppercased()) {
                return name
            }
        }
        return identifier(name)
    }

    private static func isUnquotedIdentifier(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first, isLetter(first) || first.value == 0x5F else {
            return false
        }
        return value.unicodeScalars.dropFirst().allSatisfy {
            isLetter($0) || isDigit($0) || $0.value == 0x5F
        }
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x39).contains(scalar.value)
    }

    private static func escape(_ value: String, character: Character, replacement: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for current in value {
            result += current == character ? replacement : String(current)
        }
        return result
    }

    /// Common SQL reserved words that require quoting
    private static let sqlReservedWords: Set<String> = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "LIKE", "BETWEEN",
        "IS", "NULL", "TRUE", "FALSE", "AS", "JOIN", "INNER", "LEFT", "RIGHT",
        "FULL", "CROSS", "ON", "USING", "GROUP", "BY", "HAVING", "ORDER", "ASC",
        "DESC", "LIMIT", "OFFSET", "DISTINCT", "ALL", "UNION", "INTERSECT",
        "EXCEPT", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "CREATE", "DROP", "TABLE", "INDEX", "GRAPH", "PROPERTY", "MATCH",
        "WITH", "CASE", "WHEN", "THEN", "ELSE", "END", "CAST", "COUNT",
        "SUM", "AVG", "MIN", "MAX", "EXISTS", "ANY", "SOME"
    ]
}

// MARK: - SPARQL Escaping

/// SPARQL identifier and IRI escaping utilities
public enum SPARQLEscape {
    /// Validate and return an XML NCName.
    ///
    /// Reference: W3C XML Namespaces 1.0 NCName production
    /// NCName ::= Name - (Char* ':' Char*)
    /// Name ::= NameStartChar (NameChar)*
    /// NameStartChar ::= ":" | [A-Z] | "_" | [a-z] | ...
    /// NameChar ::= NameStartChar | "-" | "." | [0-9] | ...
    ///
    public static func ncName(_ name: String) throws(SPARQLEscapeError) -> String {
        guard !name.isEmpty else {
            throw SPARQLEscapeError.emptyNCName
        }

        guard isNCName(name) else {
            throw SPARQLEscapeError.invalidNCName(name)
        }

        return name
    }

    /// Validate NCName and return it, or return nil if invalid
    public static func ncNameOrNil(_ name: String) -> String? {
        guard isNCName(name) else { return nil }
        return name
    }

    /// Validate a SPARQL `PN_PREFIX`.
    ///
    /// The empty string represents the default prefix and is valid.
    public static func prefixOrNil(_ prefix: String) -> String? {
        guard isPrefix(prefix) else { return nil }
        return prefix
    }

    /// Validate a SPARQL prefixed-name local component.
    ///
    /// The empty string is valid because a `PNAME_NS` does not require a
    /// `PN_LOCAL` suffix.
    public static func localNameOrNil(_ name: String) -> String? {
        guard isLocalName(name) else { return nil }
        return name
    }

    /// Return a valid SPARQL blank-node label for an application identifier.
    ///
    /// Valid labels are preserved. Invalid labels are encoded injectively as
    /// lowercase hexadecimal UTF-8 with a leading letter.
    public static func blankNodeLabel(_ identifier: String) -> String {
        if !identifier.isEmpty,
           isBlankNodeLabel(identifier),
           !identifier.hasPrefix("z") {
            return identifier
        }

        // Labels beginning with "z" share the encoded namespace. Encoding
        // those valid labels too keeps this transformation injective.
        var encoded = "z"
        encoded.reserveCapacity(1 + identifier.utf8.count * 2)
        for byte in identifier.utf8 {
            encoded.append(hexDigit(for: byte >> 4))
            encoded.append(hexDigit(for: byte & 0x0F))
        }
        return encoded
    }

    static func prefixedName(
        for iri: String,
        prefixes: [String: String]
    ) -> String? {
        var selected: (
            prefix: String,
            local: String,
            baseLength: Int
        )?
        for (prefix, base) in prefixes {
            guard iri.hasPrefix(base),
                  prefixOrNil(prefix) != nil else {
                continue
            }
            let local = String(iri.dropFirst(base.count))
            guard localNameOrNil(local) != nil else {
                continue
            }
            if let current = selected {
                if base.count > current.baseLength
                    || base.count == current.baseLength
                    && prefix < current.prefix {
                    selected = (prefix, local, base.count)
                }
            } else {
                selected = (prefix, local, base.count)
            }
        }
        guard let selected else {
            return nil
        }
        return "\(selected.prefix):\(selected.local)"
    }

    /// Escape IRI for SPARQL
    /// Escapes characters that are not allowed in IRIs
    ///
    /// Reference: RFC 3987 (IRI), SPARQL 1.1 Section 19.5
    public static func iri(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            if isForbiddenIRIReferenceCharacter(scalar) {
                appendPercentEncoded(UInt8(scalar.value), to: &escaped)
            } else {
                escaped.unicodeScalars.append(scalar)
            }
        }
        return "<\(escaped)>"
    }

    /// Escape string for SPARQL literal
    /// Escapes special characters in string literals
    ///
    /// Reference: SPARQL 1.1 Section 19.5
    public static func string(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: escaped += "\\b"
            case 0x09: escaped += "\\t"
            case 0x0A: escaped += "\\n"
            case 0x0C: escaped += "\\f"
            case 0x0D: escaped += "\\r"
            case 0x22: escaped += "\\\""
            case 0x5C: escaped += "\\\\"
            case 0x00...0x1F, 0x7F:
                appendUnicodeEscape(scalar.value, to: &escaped)
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"\(escaped)\""
    }

    /// Validate and format a prefixed name
    /// Returns "prefix:local" with validated components
    public static func prefixedName(
        prefix: String,
        local: String
    ) throws(SPARQLEscapeError) -> String {
        guard let validatedPrefix = prefixOrNil(prefix) else {
            throw SPARQLEscapeError.invalidPrefix(prefix)
        }
        guard localNameOrNil(local) != nil else {
            throw SPARQLEscapeError.invalidLocalName(local)
        }
        return "\(validatedPrefix):\(local)"
    }

    private static func isNCName(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first, isNameStartCharacter(first) else {
            return false
        }
        return value.unicodeScalars.dropFirst().allSatisfy(isXMLNameCharacter)
    }

    private static func isPrefix(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first else {
            return true
        }
        guard isNameBaseCharacter(first) else {
            return false
        }

        var last = first
        for scalar in value.unicodeScalars.dropFirst() {
            guard isNameCharacter(scalar) || scalar.value == 0x2E else {
                return false
            }
            last = scalar
        }
        return last.value != 0x2E
    }

    private static func isLocalName(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        guard !scalars.isEmpty else {
            return true
        }

        var index = scalars.startIndex
        guard consumeLocalToken(
            in: scalars,
            at: &index,
            allowsInitialCharacter: true
        ) else {
            return false
        }

        var finalTokenIsPeriod = false
        while index != scalars.endIndex {
            let tokenStart = index
            guard consumeLocalToken(
                in: scalars,
                at: &index,
                allowsInitialCharacter: false
            ) else {
                return false
            }
            finalTokenIsPeriod =
                scalars[tokenStart].value == 0x2E
                && scalars.index(after: tokenStart) == index
        }
        return !finalTokenIsPeriod
    }

    private static func isBlankNodeLabel(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              isNameStartCharacter(first) || isDigit(first) else {
            return false
        }

        var last = first
        for scalar in value.unicodeScalars.dropFirst() {
            guard isNameCharacter(scalar) || scalar.value == 0x2E else {
                return false
            }
            last = scalar
        }
        return last.value != 0x2E
    }

    private static func consumeLocalToken(
        in scalars: String.UnicodeScalarView,
        at index: inout String.UnicodeScalarView.Index,
        allowsInitialCharacter: Bool
    ) -> Bool {
        guard index != scalars.endIndex else {
            return false
        }

        let scalar = scalars[index]
        if scalar.value == 0x25 {
            return consumePercentEscape(in: scalars, at: &index)
        }
        if scalar.value == 0x5C {
            return consumeLocalEscape(in: scalars, at: &index)
        }

        let isAllowed = allowsInitialCharacter
            ? isNameStartCharacter(scalar)
                || isDigit(scalar)
                || scalar.value == 0x3A
            : isNameCharacter(scalar)
                || scalar.value == 0x2E
                || scalar.value == 0x3A
        guard isAllowed else {
            return false
        }
        index = scalars.index(after: index)
        return true
    }

    private static func consumePercentEscape(
        in scalars: String.UnicodeScalarView,
        at index: inout String.UnicodeScalarView.Index
    ) -> Bool {
        var cursor = scalars.index(after: index)
        guard cursor != scalars.endIndex, isHexDigit(scalars[cursor]) else {
            return false
        }
        cursor = scalars.index(after: cursor)
        guard cursor != scalars.endIndex, isHexDigit(scalars[cursor]) else {
            return false
        }
        index = scalars.index(after: cursor)
        return true
    }

    private static func consumeLocalEscape(
        in scalars: String.UnicodeScalarView,
        at index: inout String.UnicodeScalarView.Index
    ) -> Bool {
        let escapedIndex = scalars.index(after: index)
        guard escapedIndex != scalars.endIndex else {
            return false
        }
        guard isLocalEscapeCharacter(scalars[escapedIndex]) else {
            return false
        }
        index = scalars.index(after: escapedIndex)
        return true
    }

    private static func isNameStartCharacter(_ scalar: Unicode.Scalar) -> Bool {
        isNameBaseCharacter(scalar) || scalar.value == 0x5F
    }

    private static func isXMLNameCharacter(_ scalar: Unicode.Scalar) -> Bool {
        isNameCharacter(scalar) || scalar.value == 0x2E
    }

    private static func isNameCharacter(_ scalar: Unicode.Scalar) -> Bool {
        isNameStartCharacter(scalar)
            || (0x30...0x39).contains(scalar.value)
            || scalar.value == 0x2D
            || scalar.value == 0xB7
            || (0x0300...0x036F).contains(scalar.value)
            || (0x203F...0x2040).contains(scalar.value)
    }

    private static func isNameBaseCharacter(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (0x41...0x5A).contains(value)
            || (0x61...0x7A).contains(value)
            || (0xC0...0xD6).contains(value)
            || (0xD8...0xF6).contains(value)
            || (0xF8...0x2FF).contains(value)
            || (0x370...0x37D).contains(value)
            || (0x37F...0x1FFF).contains(value)
            || (0x200C...0x200D).contains(value)
            || (0x2070...0x218F).contains(value)
            || (0x2C00...0x2FEF).contains(value)
            || (0x3001...0xD7FF).contains(value)
            || (0xF900...0xFDCF).contains(value)
            || (0xFDF0...0xFFFD).contains(value)
            || (0x10000...0xEFFFF).contains(value)
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x39).contains(scalar.value)
    }

    private static func isHexDigit(_ scalar: Unicode.Scalar) -> Bool {
        isDigit(scalar)
            || (0x41...0x46).contains(scalar.value)
            || (0x61...0x66).contains(scalar.value)
    }

    private static func isForbiddenIRIReferenceCharacter(
        _ scalar: Unicode.Scalar
    ) -> Bool {
        switch scalar.value {
        case 0x00...0x20, 0x22, 0x3C, 0x3E, 0x5C, 0x5E,
             0x60, 0x7B...0x7D:
            return true
        default:
            return false
        }
    }

    private static func appendPercentEncoded(
        _ byte: UInt8,
        to output: inout String
    ) {
        output.append("%")
        output.append(uppercaseHexDigit(for: byte >> 4))
        output.append(uppercaseHexDigit(for: byte & 0x0F))
    }

    private static func appendUnicodeEscape(
        _ scalar: UInt32,
        to output: inout String
    ) {
        output += "\\u"
        output.append(uppercaseHexDigit(for: UInt8((scalar >> 12) & 0x0F)))
        output.append(uppercaseHexDigit(for: UInt8((scalar >> 8) & 0x0F)))
        output.append(uppercaseHexDigit(for: UInt8((scalar >> 4) & 0x0F)))
        output.append(uppercaseHexDigit(for: UInt8(scalar & 0x0F)))
    }

    private static func isLocalEscapeCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x21, 0x23...0x2F, 0x3B, 0x3D, 0x3F, 0x40, 0x5F, 0x7E:
            return true
        default:
            return false
        }
    }

    private static func hexDigit(for value: UInt8) -> Character {
        switch value {
        case 0: return "0"
        case 1: return "1"
        case 2: return "2"
        case 3: return "3"
        case 4: return "4"
        case 5: return "5"
        case 6: return "6"
        case 7: return "7"
        case 8: return "8"
        case 9: return "9"
        case 10: return "a"
        case 11: return "b"
        case 12: return "c"
        case 13: return "d"
        case 14: return "e"
        default: return "f"
        }
    }

    private static func uppercaseHexDigit(for value: UInt8) -> Character {
        switch value {
        case 0: return "0"
        case 1: return "1"
        case 2: return "2"
        case 3: return "3"
        case 4: return "4"
        case 5: return "5"
        case 6: return "6"
        case 7: return "7"
        case 8: return "8"
        case 9: return "9"
        case 10: return "A"
        case 11: return "B"
        case 12: return "C"
        case 13: return "D"
        case 14: return "E"
        default: return "F"
        }
    }
}

/// SPARQL escaping errors
public enum SPARQLEscapeError: Error, Sendable, Equatable {
    case emptyNCName
    case invalidNCName(String)
    case invalidPrefix(String)
    case invalidLocalName(String)
    case invalidIRI(String)
}
