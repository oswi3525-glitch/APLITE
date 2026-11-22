import UIKit

/// Resolution and overscan of the external display.
///
/// A 4K monitor runs at its full resolution by default, which makes everything on the desktop tiny; picking a lower
/// mode (1920×1080…) makes the monitor scale the picture up, so the desktop looks bigger and stays sharp. Some TVs
/// crop the edges of the picture (overscan): iOS can shrink the picture to fit inside them.
enum ExternalDisplay {
    private static weak var screen: UIScreen?
    private static var cachedResolutions: [CGSize]?
    private static let modeKey = "iDesk.displayMode"        // "1920x1080", or absent for the display's own choice
    private static let overscanKey = "iDesk.overscan"       // true: shrink the picture to fit a TV's visible area

    static func connected(_ screen: UIScreen) {
        self.screen = screen
        cachedResolutions = nil
        apply()
    }

    static func disconnected() { screen = nil; cachedResolutions = nil }

    /// The resolutions the display offers, largest first (each size once).
    static var resolutions: [CGSize] {
        if let cachedResolutions { return cachedResolutions }
        guard let screen else { return [] }
        var seen = Set<String>()
        let result = screen.availableModes.map(\.size)
            .filter { seen.insert(name(of: $0)).inserted }
            .sorted { $0.width * $0.height > $1.width * $1.height }
        cachedResolutions = result
        return result
    }

    static var resolution: CGSize? {
        get {
            guard let s = UserDefaults.standard.string(forKey: modeKey) else { return nil }
            let parts = s.split(separator: "x").compactMap { Double($0) }
            return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
        }
        set {
            if let newValue { UserDefaults.standard.set(name(of: newValue), forKey: modeKey) }
            else { UserDefaults.standard.removeObject(forKey: modeKey) }
            apply()
        }
    }

    /// Off unless chosen: scaling the picture in for a TV's hidden edges blurs every text on a monitor (which shows
    /// the whole picture anyway). A TV that cuts the edges off gets it from Settings.
    static var fitsOverscan: Bool {
        get { UserDefaults.standard.object(forKey: overscanKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: overscanKey); apply() }
    }

    static var currentResolution: CGSize? { screen?.currentMode?.size }

    static func name(of size: CGSize) -> String { "\(Int(size.width))x\(Int(size.height))" }

    /// The display's own choice, unless that is a TV-standard 480p/576p while it offers HD: some adapters and TVs
    /// report the safe 720×480 as preferred (seen with the Simulator's display too), which leaves the desktop tiny
    /// and blurry. Then the largest mode up to 1920×1080 (or the smallest above it).
    private static func automaticMode(of screen: UIScreen) -> UIScreenMode? {
        guard let preferred = screen.preferredMode else { return screen.availableModes.first }
        guard preferred.size.height < 720 else { return preferred }
        let hd = screen.availableModes.filter { $0.size.height >= 720 }
        let upTo1080 = hd.filter { $0.size.height <= 1080 }.max { $0.size.width * $0.size.height < $1.size.width * $1.size.height }
        return upTo1080 ?? hd.min { $0.size.width * $0.size.height < $1.size.width * $1.size.height } ?? preferred
    }

    private static func apply() {
        guard let screen else { return }
        let wanted = resolution.flatMap { size in screen.availableModes.first { $0.size == size } } ?? automaticMode(of: screen)
        if let wanted, screen.currentMode != wanted { screen.currentMode = wanted }
        screen.overscanCompensation = fitsOverscan ? .scale : .none
    }
}
