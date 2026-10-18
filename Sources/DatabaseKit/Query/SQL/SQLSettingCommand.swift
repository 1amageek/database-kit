/// An immutable request setting operation; nil denotes ALL.
public enum SQLSettingCommand: Sendable, Hashable {
    case set(name: SQLSettingName, value: Expression, scope: SQLSettingScope)
    case show(SQLSettingName?)
    case reset(SQLSettingName?, scope: SQLSettingScope)
}
