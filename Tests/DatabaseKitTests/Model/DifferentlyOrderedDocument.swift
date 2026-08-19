import DatabaseKit

@Polymorphable
@PolymorphicIndex(.ordered(
    name: "DifferentlyOrderedDocument_title",
    keys: [.ascending("title")]
))
protocol DifferentlyOrderedDocument:
    Polymorphable<DifferentlyOrderedDocumentPolymorphicGroup>
{
    var id: String { get }
    var title: String { get }
}
