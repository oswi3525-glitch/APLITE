import XCTest

final class FileSortingTests: XCTestCase {
    private let now = Date()
    private func item(_ name: String, _ size: Int64, folder: Bool = false, offset: TimeInterval = 0) -> FileSorting.Sortable {
        FileSorting.Sortable(name: name, date: now.addingTimeInterval(offset), size: size, isFolder: folder)
    }

    func testFoldersAlwaysComeFirst() {
        let list = [item("z.txt", 10), item("A", 0, folder: true), item("a.txt", 5)]
        let names = FileSorting.sorted(list, by: .name, ascending: true).map(\.name)
        XCTAssertEqual(names.first, "A")
    }

    func testSizeSortingBothDirections() {
        let list = [item("big", 900), item("small", 10), item("mid", 100)]
        XCTAssertEqual(FileSorting.sorted(list, by: .size, ascending: true).map(\.name), ["small", "mid", "big"])
        XCTAssertEqual(FileSorting.sorted(list, by: .size, ascending: false).map(\.name), ["big", "mid", "small"])
    }

    func testDateSortingAndStableNameTieBreak() {
        let list = [item("b", 1, offset: 20), item("a", 1, offset: 10), item("c", 1, offset: 10)]
        XCTAssertEqual(FileSorting.sorted(list, by: .date, ascending: true).map(\.name), ["a", "c", "b"])
    }
}
