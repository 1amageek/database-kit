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
        .ordered(
            name: "calendar_entries_by_start",
            keys: [
                .ascending(\DeclarationCalendarEntry.calendarID),
                .ascending(\DeclarationCalendarEntry.startsAt),
            ]
        )
    )

    var id: String
    var calendarID: String
    var startsAt: Int64
    var status: DeclarationCalendarStatus

    @Relationship(deleteRule: .deny)
    var owner: PersistableReference<DeclarationPrincipal>
}
