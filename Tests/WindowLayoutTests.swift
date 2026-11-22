import XCTest

final class WindowLayoutTests: XCTestCase {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func testGridCoversAllWindowsWithoutOverlap() {
        let frames = WindowLayout.grid(count: 6, in: area)
        XCTAssertEqual(frames.count, 6)
        for i in 0..<frames.count {
            for j in (i + 1)..<frames.count {
                XCTAssertFalse(frames[i].intersects(frames[j]), "frames \(i) and \(j) overlap")
            }
        }
    }

    func testEmptyAndSingle() {
        XCTAssertTrue(WindowLayout.grid(count: 0, in: area).isEmpty)
        XCTAssertEqual(WindowLayout.grid(count: 1, in: area).first?.size, area.size)
    }

    func testClampKeepsWindowInsideArea() {
        let outside = CGRect(x: 900, y: 580, width: 800, height: 600)
        let clamped = WindowLayout.clamp(outside, to: area)
        XCTAssertLessThanOrEqual(clamped.minX, area.maxX)
        XCTAssertLessThanOrEqual(clamped.minY, area.maxY)
        XCTAssertLessThanOrEqual(clamped.maxX, area.maxX + 0.001)
        XCTAssertLessThanOrEqual(clamped.maxY, area.maxY + 0.001)
    }

    func testSnapshotsAreValueEquatable() {
        let id = UUID()
        let a = WindowSnapshot(id: id, frame: area, minimized: false, maximized: true, keepOnTop: false)
        let b = WindowSnapshot(id: id, frame: area, minimized: false, maximized: true, keepOnTop: false)
        XCTAssertEqual(a, b)
    }
}
