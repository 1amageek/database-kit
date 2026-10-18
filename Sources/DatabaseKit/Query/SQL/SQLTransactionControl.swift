/// A normalized request transaction boundary.
public enum SQLTransactionControl: Sendable, Hashable { case begin, commit, rollback }
