import DatabaseKit

@Polymorphable
@PolymorphicIndex(
    .scalar,
    fields: ["title"],
    name: "DifferentlyOrderedDocument_title"
)
protocol DifferentlyOrderedDocument:
    Polymorphable<DifferentlyOrderedDocumentPolymorphicGroup>
{
    var id: String { get }
    var title: String { get }
}
