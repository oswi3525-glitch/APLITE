import XCTest

final class TrashPolicyTests: XCTestCase {
    func testSystemItemsAreProtected() {
        XCTAssertEqual(TrashPolicy.outcome(systemPage: true, trash: false, file: false,
                                           webApp: false, guestApp: false, guestRemovable: true),
                       .unsupportedSystemItem)
        XCTAssertEqual(TrashPolicy.outcome(systemPage: false, trash: true, file: false,
                                           webApp: false, guestApp: false, guestRemovable: true),
                       .unsupportedSystemItem)
    }

    func testEachOwnedCategoryGetsItsOwnOutcome() {
        XCTAssertEqual(TrashPolicy.outcome(systemPage: false, trash: false, file: true,
                                           webApp: false, guestApp: false, guestRemovable: false),
                       .moveFileToTrash)
        XCTAssertEqual(TrashPolicy.outcome(systemPage: false, trash: false, file: false,
                                           webApp: true, guestApp: false, guestRemovable: false),
                       .uninstallWebApp)
        XCTAssertEqual(TrashPolicy.outcome(systemPage: false, trash: false, file: false,
                                           webApp: false, guestApp: true, guestRemovable: true),
                       .uninstallGuestApp)
        XCTAssertEqual(TrashPolicy.outcome(systemPage: false, trash: false, file: false,
                                           webApp: false, guestApp: true, guestRemovable: false),
                       .markGuestForReinstall)
        XCTAssertEqual(TrashPolicy.outcome(systemPage: false, trash: false, file: false,
                                           webApp: false, guestApp: false, guestRemovable: false),
                       .removeShortcut)
    }
}
