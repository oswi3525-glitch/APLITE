import XCTest

final class ProjectAnalyzerTests: XCTestCase {
    func testRecognisesXcodeGenProjectAndDependencies() {
        let files = [
            (name: "project.yml", text: """
            name: Demo
            settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: com.example.demo
            packages:
              Alamofire:
                url: https://github.com/Alamofire/Alamofire
            """),
            (name: "App.swift", text: "import SwiftUI\nstruct App: App {}"),
            (name: "Info.plist", text: "<plist></plist>"),
        ]
        let a = ProjectAnalyzer.analyze(files: files)
        XCTAssertTrue(a.hasXcodeGenSpec)
        XCTAssertTrue(a.hasInfoPlist)
        XCTAssertEqual(a.swiftFiles, 1)
        XCTAssertEqual(a.bundleID, "com.example.demo")
        XCTAssertTrue(a.dependencies.contains("https://github.com/Alamofire/Alamofire"))
        XCTAssertTrue(a.needsMacOSWorker)
    }

    func testEmptyProjectWarnsAndNeverClaimsSuccess() {
        let a = ProjectAnalyzer.analyze(files: [(name: "notes.txt", text: "hello")])
        XCTAssertEqual(a.swiftFiles, 0)
        XCTAssertFalse(a.needsMacOSWorker)
        XCTAssertFalse(a.warnings.isEmpty)
    }

    func testBundleIDPatterns() {
        XCTAssertEqual(ProjectAnalyzer.extractBundleID("PRODUCT_BUNDLE_IDENTIFIER = com.hieuk.aplite;"), "com.hieuk.aplite")
        XCTAssertEqual(ProjectAnalyzer.extractBundleID("CFBundleIdentifier\" : \"org.test.app\""), "org.test.app")
    }
}
