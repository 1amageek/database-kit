import DatabaseKit
import DatabaseTypes

@Persistable
struct PersistablePrimitiveTestDocument {
    var id: String = "fixture-id"
    var decimal: DatabaseTypes.ExactDecimal
    var bytes: DatabaseTypes.ByteString
    var date: DatabaseTypes.CivilDate
    var time: DatabaseTypes.CivilTime
    var dateTime: DatabaseTypes.CivilDateTime
    var timestamp: DatabaseTypes.Timestamp
    var timeSpan: DatabaseTypes.TimeSpan
    var calendarPeriod: DatabaseTypes.CalendarPeriod
    var geographicPoint: DatabaseTypes.GeographicPoint
    var geographicPosition: DatabaseTypes.GeographicPosition
    var vector: DatabaseTypes.Vector
    var uuid: DatabaseTypes.UUID
    var object: DatabaseTypes.FieldObject
    var reference: DatabaseTypes.EntityReference
    var rdfTerm: DatabaseTypes.RDFTerm
}
