import DatabaseKit

@Persistable
struct DeclarationCalendarEntry {
    #Directory<DeclarationCalendarEntry>(
        "declaration-calendars",
        \DeclarationCalendarEntry.calendarID,
        "entries",
        layer: .partition
    )
    #Index(
        .scalar,
        fields: [
            \DeclarationCalendarEntry.calendarID,
            \DeclarationCalendarEntry.startsAt
        ]
    )

    var id: String
    var calendarID: String
    var startsAt: Int64

    @Relationship(deleteRule: .deny)
    var owner: PersistableReference<DeclarationPrincipal>
}
