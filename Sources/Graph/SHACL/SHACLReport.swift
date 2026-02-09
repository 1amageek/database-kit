// SHACLReport.swift
// Graph - SHACL validation report
//
// Reference: W3C SHACL §3.6 (Validation Report)
// https://www.w3.org/TR/shacl/#validation-report

import Foundation

/// SHACL Validation Report
///
/// The result of validating a data graph against a shapes graph.
///
/// **Example**:
/// ```swift
/// let report = try await context.shacl.validate(against: "ex:PersonShapes")
///
/// if report.conforms {
///     print("Data graph conforms to all shapes")
/// } else {
///     for violation in report.violations {
///         print("\(violation.focusNode): \(violation.resultMessage)")
///     }
/// }
/// ```
///
/// Reference: W3C SHACL §3.6.1
public struct SHACLValidationReport: Sendable, Codable {

    /// sh:conforms — true if no violations were found
    public let conforms: Bool

    /// sh:result — all validation results
    public let results: [SHACLValidationResult]

    public init(conforms: Bool, results: [SHACLValidationResult]) {
        self.conforms = conforms
        self.results = results
    }

    /// Create from a list of results (conforms = no violations)
    public init(results: [SHACLValidationResult]) {
        self.results = results
        self.conforms = !results.contains { $0.resultSeverity == .violation }
    }
}

// MARK: - Convenience Accessors

extension SHACLValidationReport {
    /// Results with severity sh:Violation
    public var violations: [SHACLValidationResult] {
        results.filter { $0.resultSeverity == .violation }
    }

    /// Results with severity sh:Warning
    public var warnings: [SHACLValidationResult] {
        results.filter { $0.resultSeverity == .warning }
    }

    /// Results with severity sh:Info
    public var infos: [SHACLValidationResult] {
        results.filter { $0.resultSeverity == .info }
    }

    /// Total number of results
    public var resultCount: Int {
        results.count
    }

    /// Results grouped by focus node
    public var resultsByFocusNode: [String: [SHACLValidationResult]] {
        Dictionary(grouping: results, by: \.focusNode)
    }

    /// Results grouped by source shape IRI
    public var resultsBySourceShape: [String: [SHACLValidationResult]] {
        var grouped: [String: [SHACLValidationResult]] = [:]
        for result in results {
            let key = result.sourceShape ?? "_:unknown"
            grouped[key, default: []].append(result)
        }
        return grouped
    }

    /// Merge with another report
    public func merged(with other: SHACLValidationReport) -> SHACLValidationReport {
        SHACLValidationReport(results: results + other.results)
    }
}

// MARK: - SHACLValidationResult

/// SHACL Validation Result
///
/// A single validation result indicating a constraint violation, warning, or info.
///
/// Reference: W3C SHACL §3.6.2
public struct SHACLValidationResult: Sendable, Codable {

    /// sh:focusNode — the node that was validated
    public let focusNode: String

    /// sh:resultPath — the property path (for property shape results)
    public let resultPath: SHACLPath?

    /// sh:value — the value node that violated the constraint
    public let value: SHACLValue?

    /// sh:sourceConstraintComponent — IRI of the constraint component
    public let sourceConstraintComponent: String

    /// sh:sourceShape — IRI of the shape that produced this result
    public let sourceShape: String?

    /// sh:resultMessage — human-readable descriptions
    public let resultMessage: [String]

    /// sh:resultSeverity — severity level
    public let resultSeverity: SHACLSeverity

    public init(
        focusNode: String,
        resultPath: SHACLPath? = nil,
        value: SHACLValue? = nil,
        sourceConstraintComponent: String,
        sourceShape: String? = nil,
        resultMessage: [String] = [],
        resultSeverity: SHACLSeverity = .violation
    ) {
        self.focusNode = focusNode
        self.resultPath = resultPath
        self.value = value
        self.sourceConstraintComponent = sourceConstraintComponent
        self.sourceShape = sourceShape
        self.resultMessage = resultMessage
        self.resultSeverity = resultSeverity
    }
}

// MARK: - CustomStringConvertible

extension SHACLValidationReport: CustomStringConvertible {
    public var description: String {
        if conforms {
            return "ValidationReport(conforms: true)"
        }
        var lines = ["ValidationReport(conforms: false, \(results.count) results)"]
        for result in results {
            lines.append("  \(result)")
        }
        return lines.joined(separator: "\n")
    }
}

extension SHACLValidationResult: CustomStringConvertible {
    public var description: String {
        var parts = ["\(resultSeverity): focusNode=\(focusNode)"]
        if let path = resultPath {
            parts.append("path=\(path)")
        }
        if let value = value {
            parts.append("value=\(value)")
        }
        if let msg = resultMessage.first {
            parts.append("message=\"\(msg)\"")
        }
        return parts.joined(separator: ", ")
    }
}
