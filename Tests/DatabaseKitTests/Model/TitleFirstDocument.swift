import DatabaseKit

@Persistable
struct TitleFirstDocument: DifferentlyOrderedDocument {
    var title: String
    var id: String
}
