import UIKit

/// APLite runs on iPhone and iPad: the texts about the device itself name the one it runs on.
enum Device {
    static let isPad = UIDevice.current.userInterfaceIdiom == .pad

    /// "iPhone" becomes "iPad" on an iPad (the same word in every language APLite speaks).
    static func words(_ s: String) -> String { isPad ? s.replacingOccurrences(of: "iPhone", with: "iPad") : s }
}
