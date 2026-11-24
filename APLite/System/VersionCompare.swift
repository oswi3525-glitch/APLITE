import Foundation

/// Pure version ordering. A prerelease suffix must not sort *above* its stable version:
/// `1.3.0-beta.1` and `1.3.0` have the same numeric version, so no update is offered.
enum VersionCompare {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let x = numbers(candidate), y = numbers(current)
        for index in 0..<max(x.count, y.count) {
            let left = index < x.count ? x[index] : 0
            let right = index < y.count ? y[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func numbers(_ version: String) -> [Int] {
        version.split(separator: "-", maxSplits: 1)[0]
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }
}
