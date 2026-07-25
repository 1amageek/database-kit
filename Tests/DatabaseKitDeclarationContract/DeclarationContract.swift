import DatabaseTypes
import DatabaseKit

enum DeclarationContract {
    static let calendarField: Field<DeclarationCalendarEntry, String> = #field(
        \DeclarationCalendarEntry.calendarID
    )

    static func schema() throws(DeclarationContractError) -> Schema {
        let entities: [Schema.Entity]
        do {
            entities = [
                try DeclarationPrincipal.schemaEntity,
                try DeclarationCalendarEntry.schemaEntity
            ]
        } catch let failure {
            throw .invalidEntity(failure)
        }

        do {
            return try Schema(
                entities: entities,
                version: Schema.Version(1, 0, 0)
            )
        } catch let failure {
            throw .invalidSchema(failure)
        }
    }
}
