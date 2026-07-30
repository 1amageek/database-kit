/// DatabaseKit uses DatabaseTypes as its canonical primitive vocabulary.
///
/// Re-exporting the primitive module keeps macro-generated model conformances
/// hygienic: importing DatabaseKit is sufficient to name the exact primitive
/// types that appear in Persistable requirements. Ownership of those types
/// remains in DatabaseTypes.
@_exported import DatabaseTypes
