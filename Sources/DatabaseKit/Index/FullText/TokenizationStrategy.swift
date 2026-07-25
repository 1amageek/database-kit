/// Token boundary policy used by a full-text index.
public enum TokenizationStrategy: String, Sendable, Hashable {
    case simple
    case stem
    case ngram
    case keyword
}
