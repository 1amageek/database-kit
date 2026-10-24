import DatabaseKit

@Persistable
struct FluentPerson {
    var id: String = "person"
    var name: String = "Name"
    var age: Int32 = 20
    var isActive: Bool = true
    var nickname: String? = nil
}
