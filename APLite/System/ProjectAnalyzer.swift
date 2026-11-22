import Foundation

/// What can honestly be learned about a build project on iOS. Xcode is not available here, so
/// this reports facts from the files only — it never claims a build succeeded.
struct ProjectAnalysis: Equatable {
    let name: String
    let swiftFiles: Int
    let hasXcodeProject: Bool
    let hasXcodeGenSpec: Bool
    let hasPackageSwift: Bool
    let hasInfoPlist: Bool
    let hasProvisioningProfile: Bool
    let bundleID: String?
    let dependencies: [String]
    let warnings: [String]
    /// swift / python / node — decides which kind of macOS worker is needed.
    let language: String
    let hasPython: Bool
    let hasNode: Bool

    var needsMacOSWorker: Bool { language == "swift" && (hasXcodeProject || hasXcodeGenSpec || hasPackageSwift) }

    var summary: String {
        var parts = ["\(swiftFiles) Swift files"]
        if hasXcodeProject { parts.append("Xcode project") }
        if hasXcodeGenSpec { parts.append("XcodeGen spec") }
        if hasPackageSwift { parts.append("Swift package") }
        if hasProvisioningProfile { parts.append("provisioning profile") }
        return parts.joined(separator: " · ")
    }
}

/// Pure source analysis (unit tested): no filesystem, no network, no Xcode.
enum ProjectAnalyzer {
    static func analyze(files: [(name: String, text: String)]) -> ProjectAnalysis {
        var swift = 0, xcodeProject = false, xcodegen = false, package = false, plist = false, profile = false
        var python = false, node = false
        var bundleID: String?
        var dependencies: [String] = []
        var warnings: [String] = []

        for file in files {
            let name = file.name.lowercased()
            if name.hasSuffix(".swift") { swift += 1 }
            if name.hasSuffix(".py") || name == "requirements.txt" { python = true }
            if name.hasSuffix(".js") || name == "package.json" { node = true }
            if name.hasSuffix(".xcodeproj/project.pbxproj") || name.hasSuffix(".xcodeproj") { xcodeProject = true }
            if name == "project.yml" || name == "project.yaml" { xcodegen = true }
            if name == "package.swift" { package = true }
            if name == "info.plist" { plist = true }
            if name.hasSuffix(".mobileprovision") || name.hasSuffix(".provisionprofile") { profile = true }

            if let id = extractBundleID(file.text) { bundleID = id }
            dependencies.append(contentsOf: extractDependencies(file.text))
        }
        dependencies = Array(Set(dependencies)).sorted()

        if swift == 0 { warnings.append(String(localized: "No Swift sources were found in the selected files.")) }
        if !xcodeProject && !xcodegen && !package {
            warnings.append(String(localized: "No Xcode project, XcodeGen spec or Package.swift was found. A macOS build worker needs one of them."))
        }
        if bundleID == nil {
            warnings.append(String(localized: "No Bundle ID was found; configure one before requesting a build."))
        }

        let language = python && !node ? "python" : node && !python ? "node" : node && python ? "mixed" : "swift"
        return ProjectAnalysis(name: files.first?.name ?? String(localized: "Imported project"),
                               swiftFiles: swift, hasXcodeProject: xcodeProject, hasXcodeGenSpec: xcodegen,
                               hasPackageSwift: package, hasInfoPlist: plist, hasProvisioningProfile: profile,
                               bundleID: bundleID, dependencies: dependencies, warnings: warnings,
                               language: language, hasPython: python, hasNode: node)
    }

    /// Recognises `PRODUCT_BUNDLE_IDENTIFIER = com.example.app;` and `"CFBundleIdentifier": "..."`.
    static func extractBundleID(_ text: String) -> String? {
        let patterns = ["PRODUCT_BUNDLE_IDENTIFIER\\s*[:=]\\s*\"?([A-Za-z0-9.]+)",
                        "CFBundleIdentifier\"?\\s*[:=]\\s*\"?([A-Za-z0-9.]+)"]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
               let found = Range(match.range(at: 1), in: text) {
                return String(text[found])
            }
        }
        return nil
    }

    /// Recognises Swift Package Manager `.package(url: "…")` and CocoaPods `pod '…'`.
    static func extractDependencies(_ text: String) -> [String] {
        var result: [String] = []
        // SwiftPM manifest, CocoaPods, and the `url:` lines of an XcodeGen project.yml.
        for pattern in [#".package\(\s*url\s*:\s*"([^"]+)""#, #"pod\s+'([^']+)'"#,
                        #"(?m)^\s*url:\s*(https?://[^\s"']+)"#] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard match.numberOfRanges > 1, let found = Range(match.range(at: 1), in: text) else { continue }
                result.append(String(text[found]))
            }
        }
        return result
    }
}
