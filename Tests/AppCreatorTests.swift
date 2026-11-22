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

    func testPythonAndNodeTemplates() {
        let py = AppCreatorTemplates.files(template: .python, displayName: "Py Tool", bundleID: "com.test.py")
        XCTAssertNotNil(py["main.py"])
        XCTAssertNotNil(py["requirements.txt"])
        XCTAssertTrue(py["project.json"]!.contains("\"language\" : \"python\"") || py["project.json"]!.contains("\"language\": \"python\""))

        let js = AppCreatorTemplates.files(template: .node, displayName: "Node Tool", bundleID: "com.test.node")
        XCTAssertNotNil(js["index.js"])
        XCTAssertNotNil(js["package.json"])
        XCTAssertTrue(js["package.json"]!.contains("\"start\""))
    }

    func testAllTemplatesProduceCompilableShapes() {
        for template in AppTemplate.allCases {
            let files = AppCreatorTemplates.files(template: template, displayName: "X", bundleID: "com.test.x")
            XCTAssertEqual(files.count, 4)
            XCTAssertTrue(files.values.allSatisfy { !$0.isEmpty })
        }
    }
}
