import DatabaseTypes

/// Retention policy for a version index.
public enum VersionHistoryStrategy: Sendable, Hashable {
    /// Retain every persisted version.
    case keepAll

    /// Retain only the most recent number of versions.
    case keepLast(Int)

    /// Retain versions for the specified exact duration.
    case keepForDuration(TimeSpan)
}
