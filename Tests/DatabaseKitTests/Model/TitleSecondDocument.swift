import DatabaseKit

@Persistable
struct TitleSecondDocument: DifferentlyOrderedDocument {
    var id: String
    var title: String
}
