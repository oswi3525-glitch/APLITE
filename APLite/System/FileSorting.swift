import Foundation

/// Pure file sorting, shared by the Files page and the unit tests.
enum FileSorting {
    enum Key: String { case name, date, size }

    struct Sortable {
        let name: String
        let date: Date
        let size: Int64
        let isFolder: Bool
    }

    /// Folders always come first; then the chosen key; then name as a stable tie-breaker.
    static func sorted(_ items: [Sortable], by key: Key, ascending: Bool) -> [Sortable] {
        items.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            let order: ComparisonResult
            switch key {
            case .name: order = a.name.localizedCaseInsensitiveCompare(b.name)
            case .date: order = a.date == b.date ? .orderedSame : (a.date < b.date ? .orderedAscending : .orderedDescending)
            case .size: order = a.size == b.size ? .orderedSame : (a.size < b.size ? .orderedAscending : .orderedDescending)
            }
            let effective = ascending ? order : flip(order)
            if effective != .orderedSame { return effective == .orderedAscending }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private static func flip(_ order: ComparisonResult) -> ComparisonResult {
        order == .orderedAscending ? .orderedDescending : order == .orderedDescending ? .orderedAscending : .orderedSame
    }
}
