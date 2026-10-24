import DatabaseKit

@Persistable
struct FluentRuntimePerson {
    var id: String = "person"
    var name: String = "Name"
    var age: Int32 = 20
}
