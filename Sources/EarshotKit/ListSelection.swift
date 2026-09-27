/// What a list selects once the rows it had selected are deleted.
public enum ListSelection {
    /// The first row left after the last deleted one, as Mail and Notes move on to the next
    /// message or note; the nearest one before it when nothing is left below. Nil when no row is
    /// left, or none of `deleted` is in `order`.
    public static func next<ID: Hashable>(afterDeleting deleted: Set<ID>, in order: [ID]) -> ID? {
        guard let last = order.lastIndex(where: deleted.contains) else { return nil }
        return order[(last + 1)...].first { !deleted.contains($0) }
            ?? order[..<last].last { !deleted.contains($0) }
    }
}
