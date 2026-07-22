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
    /// Validate and return NCName (prefix/local name)
    ///
    /// Reference: W3C XML Namespaces 1.0 NCName production
    /// NCName ::= Name - (Char* ':' Char*)
    /// Name ::= NameStartChar (NameChar)*
    /// NameStartChar ::= ":" | [A-Z] | "_" | [a-z] | ...
    /// NameChar ::= NameStartChar | "-" | "." | [0-9] | ...
    ///
    /// Simplified pattern for common use cases
    public static func ncName(_ name: String) throws -> String {
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

    public static func localNameOrNil(_ name: String) -> String? {
        guard name.unicodeScalars.allSatisfy(isNameCharacter) else { return nil }
        return name
    }

    /// Escape IRI for SPARQL
    /// Escapes characters that are not allowed in IRIs
    ///
    /// Reference: RFC 3987 (IRI), SPARQL 1.1 Section 19.5
    public static func iri(_ value: String) -> String {
        // Escape characters not allowed in IRIs: < > " { } | ^ ` \
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "\\": escaped += "%5C"
            case "<": escaped += "%3C"
            case ">": escaped += "%3E"
            case "\"": escaped += "%22"
            case "{": escaped += "%7B"
            case "}": escaped += "%7D"
            case "|": escaped += "%7C"
            case "^": escaped += "%5E"
            case "`": escaped += "%60"
            default: escaped.append(character)
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
        for character in value {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default: escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }

    /// Validate and format a prefixed name
    /// Returns "prefix:local" with validated components
    public static func prefixedName(prefix: String, local: String) throws -> String {
        let validatedPrefix = try ncName(prefix)
        // Local part can be empty or valid NCName characters
        if !local.isEmpty {
            // Local part allows more characters than prefix
            guard local.unicodeScalars.allSatisfy(isNameCharacter) else {
                throw SPARQLEscapeError.invalidLocalName(local)
            }
        }
        return "\(validatedPrefix):\(local)"
    }

    private static func isNCName(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first, isLetter(first) || first.value == 0x5F else {
            return false
        }
        return value.unicodeScalars.dropFirst().allSatisfy(isNameCharacter)
    }

    private static func isNameCharacter(_ scalar: Unicode.Scalar) -> Bool {
        isLetter(scalar)
            || (0x30...0x39).contains(scalar.value)
            || scalar.value == 0x5F
            || scalar.value == 0x2E
            || scalar.value == 0x2D
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
    }
}

/// SPARQL escaping errors
public enum SPARQLEscapeError: Error, Sendable, Equatable {
    case emptyNCName
    case invalidNCName(String)
    case invalidLocalName(String)
    case invalidIRI(String)
}
