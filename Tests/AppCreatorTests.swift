import XCTest

final class AppCreatorTests: XCTestCase {
    func testModuleNameSanitisation() {
        XCTAssertEqual(AppCreatorTemplates.moduleName("My Cool App!"), "MyCoolApp")
        XCTAssertEqual(AppCreatorTemplates.moduleName("123 app"), "App123app")
        XCTAssertEqual(AppCreatorTemplates.moduleName(""), "APLiteApp")
    }

    func testGeneratedProjectIsInternallyConsistent() {
        let files = AppCreatorTemplates.files(template: .webView, displayName: "Demo", bundleID: "com.example.demo")
        XCTAssertNotNil(files["project.yml"])
        XCTAssertNotNil(files["Sources/DemoApp.swift"])
        XCTAssertNotNil(files["Sources/ContentView.swift"])
        XCTAssertTrue(files["project.yml"]!.contains("PRODUCT_BUNDLE_IDENTIFIER: com.example.demo"))
        XCTAssertTrue(files["project.yml"]!.contains("sources: [Sources]"))
        XCTAssertTrue(files["Sources/DemoApp.swift"]!.contains("struct DemoApp: App"))
        XCTAssertTrue(files["Sources/ContentView.swift"]!.contains("WKWebView"))
    }

    func testAllTemplatesProduceCompilableShapes() {
        for template in AppTemplate.allCases {
            let files = AppCreatorTemplates.files(template: template, displayName: "X", bundleID: "com.test.x")
            XCTAssertEqual(files.count, 4)
            XCTAssertTrue(files.values.allSatisfy { !$0.isEmpty })
        }
    }
}
