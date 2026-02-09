// PrefixMap.swift
// Graph - IRI prefix/namespace management
//
// Provides bidirectional expansion and compaction of prefixed IRIs.
//
// Reference: W3C RDF 1.1 Turtle §2.4 (Prefixed Names)
// https://www.w3.org/TR/turtle/#prefixed-name

import Foundation

/// Bidirectional IRI prefix map
///
/// Manages prefix-to-namespace mappings for expanding and compacting IRIs.
///
/// **Example**:
/// ```swift
/// var prefixes = PrefixMap.standard
/// prefixes.register(prefix: "ex", namespace: "http://example.org/")
///
/// prefixes.expand("ex:Person")    // → "http://example.org/Person"
/// prefixes.compact("http://example.org/Person")  // → "ex:Person"
/// ```
public struct PrefixMap: Sendable, Codable, Hashable {

    // MARK: - Storage

    /// prefix → namespace IRI mapping
    private var prefixToNamespace: [String: String]

    // MARK: - Initialization

    /// Create a prefix map with given mappings
    public init(_ prefixes: [String: String] = [:]) {
        self.prefixToNamespace = prefixes
    }

    /// Create from OWL ontology prefixes
    public init(fromOntologyPrefixes prefixes: [String: String]) {
        self.prefixToNamespace = prefixes
    }

    // MARK: - Standard Prefixes

    /// W3C standard and common vocabulary prefixes
    ///
    /// Includes:
    /// - `rdf`, `rdfs`, `owl`, `xsd` — W3C core
    /// - `sh` — SHACL
    /// - `skos` — Simple Knowledge Organization System
    /// - `dcterms` — Dublin Core Terms
    /// - `foaf` — Friend of a Friend
    /// - `schema` — Schema.org
    public static let standard = PrefixMap([
        "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
        "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
        "owl": "http://www.w3.org/2002/07/owl#",
        "xsd": "http://www.w3.org/2001/XMLSchema#",
        "sh": "http://www.w3.org/ns/shacl#",
        "skos": "http://www.w3.org/2004/02/skos/core#",
        "dcterms": "http://purl.org/dc/terms/",
        "foaf": "http://xmlns.com/foaf/0.1/",
        "schema": "https://schema.org/",
    ])

    /// Empty prefix map
    public static let empty = PrefixMap()

    // MARK: - Registration

    /// Register a prefix-namespace mapping
    ///
    /// - Parameters:
    ///   - prefix: The short prefix (e.g., "ex")
    ///   - namespace: The full namespace IRI (e.g., "http://example.org/")
    public mutating func register(prefix: String, namespace: String) {
        prefixToNamespace[prefix] = namespace
    }

    /// Remove a prefix mapping
    public mutating func remove(prefix: String) {
        prefixToNamespace.removeValue(forKey: prefix)
    }

    // MARK: - Expansion

    /// Expand a prefixed name to a full IRI
    ///
    /// If the input contains a colon and the prefix is registered,
    /// the prefix is replaced with the namespace IRI.
    /// If no matching prefix is found, returns the input unchanged.
    ///
    /// - Parameter prefixed: A prefixed name (e.g., "sh:NodeShape")
    /// - Returns: The expanded IRI (e.g., "http://www.w3.org/ns/shacl#NodeShape")
    public func expand(_ prefixed: String) -> String {
        guard let colonIndex = prefixed.firstIndex(of: ":") else {
            return prefixed
        }

        let prefix = String(prefixed[prefixed.startIndex..<colonIndex])
        let localName = String(prefixed[prefixed.index(after: colonIndex)...])

        // Check for full IRI (contains "//") — do not expand
        if localName.hasPrefix("//") {
            return prefixed
        }

        guard let namespace = prefixToNamespace[prefix] else {
            return prefixed
        }

        return namespace + localName
    }

    /// Check if a string is a prefixed name that can be expanded
    public func canExpand(_ prefixed: String) -> Bool {
        guard let colonIndex = prefixed.firstIndex(of: ":") else {
            return false
        }
        let prefix = String(prefixed[prefixed.startIndex..<colonIndex])
        let localName = String(prefixed[prefixed.index(after: colonIndex)...])
        return !localName.hasPrefix("//") && prefixToNamespace[prefix] != nil
    }

    // MARK: - Compaction

    /// Compact a full IRI to a prefixed name
    ///
    /// Finds the longest matching namespace and replaces it with the prefix.
    /// If no matching namespace is found, returns the input unchanged.
    ///
    /// - Parameter fullIRI: A full IRI (e.g., "http://www.w3.org/ns/shacl#NodeShape")
    /// - Returns: The compacted form (e.g., "sh:NodeShape")
    public func compact(_ fullIRI: String) -> String {
        var bestPrefix: String?
        var bestNamespace: String?
        var bestLength = 0

        for (prefix, namespace) in prefixToNamespace {
            if fullIRI.hasPrefix(namespace) && namespace.count > bestLength {
                bestPrefix = prefix
                bestNamespace = namespace
                bestLength = namespace.count
            }
        }

        guard let prefix = bestPrefix, let namespace = bestNamespace else {
            return fullIRI
        }

        let localName = String(fullIRI.dropFirst(namespace.count))
        return "\(prefix):\(localName)"
    }

    // MARK: - Composition

    /// Create a new prefix map by merging with another
    ///
    /// The other map's prefixes take precedence on conflicts.
    public func merged(with other: PrefixMap) -> PrefixMap {
        var result = self.prefixToNamespace
        for (prefix, namespace) in other.prefixToNamespace {
            result[prefix] = namespace
        }
        return PrefixMap(result)
    }

    // MARK: - Access

    /// All registered prefixes
    public var prefixes: [String] {
        Array(prefixToNamespace.keys).sorted()
    }

    /// All registered mappings
    public var mappings: [String: String] {
        prefixToNamespace
    }

    /// Get namespace for a prefix
    public func namespace(for prefix: String) -> String? {
        prefixToNamespace[prefix]
    }

    /// Get prefix for a namespace
    public func prefix(for namespace: String) -> String? {
        prefixToNamespace.first { $0.value == namespace }?.key
    }

    /// Number of registered prefixes
    public var count: Int {
        prefixToNamespace.count
    }

    /// Whether the map is empty
    public var isEmpty: Bool {
        prefixToNamespace.isEmpty
    }
}

// MARK: - ExpressibleByDictionaryLiteral

extension PrefixMap: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, String)...) {
        self.prefixToNamespace = Dictionary(uniqueKeysWithValues: elements)
    }
}

// MARK: - CustomStringConvertible

extension PrefixMap: CustomStringConvertible {
    public var description: String {
        let entries = prefixToNamespace.sorted { $0.key < $1.key }
            .map { "@prefix \($0.key): <\($0.value)> ." }
            .joined(separator: "\n")
        return "PrefixMap(\(prefixToNamespace.count) prefixes)\n\(entries)"
    }
}
