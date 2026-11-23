import SwiftUI

/// One place that names the visual assets APLite owns.
///
/// 1.3.0 keeps the existing SF Symbol-based views untouched — this registry is additive. It records
/// which licensed icon families ship as a local *source library* (never hot-linked, never bundled
/// wholesale into the app) and the canonical names APLite uses for each concept. A later release
/// can switch a family or an individual glyph here instead of editing every view.
///
/// The library itself lives in `Assets/Icons/` at the repository root, outside the `APLite/`
/// source folder, so XcodeGen does not copy it into the application target.
enum AssetRegistry {
    /// Licensed icon source libraries. Attribution and full licence text live beside each set.
    enum Family: String, CaseIterable {
        case tabler = "Tabler"
        case lucide = "Lucide"

        var libraryPath: String {
            switch self {
            case .tabler: return "Assets/Icons/Tabler"
            case .lucide: return "Assets/Icons/Lucide"
            }
        }
    }

    /// A concept the APLite UI refers to, independent of the icon family that draws it.
    ///
    /// `rawValue` is the shared kebab-case glyph name verified to exist in **both** Tabler outline
    /// and Lucide. Keeping one name per concept avoids two sets of hardcoded strings in views.
    enum Icon: String, CaseIterable {
        case folder, file, settings, trash, lock, wifi, battery, keyboard, bell, search
        case terminal, download, upload
        case close = "x"
        case maximize, minimize
        case chevronRight = "chevron-right"
        case plus, check, power, moon, sun, shield, key, calendar, clock, link, copy, clipboard
        case appWindow = "app-window"
        case chartBar = "chart-bar"
        case cloud, plug, bluetooth, volume, camera
        case mapPin = "map-pin"
        case mail
        case shieldCheck = "shield-check"
        case code, palette, list

        /// The SF Symbol used by native SwiftUI today. This is the value views should read.
        var sfSymbol: String {
            switch self {
            case .folder: return "folder"
            case .file: return "doc"
            case .settings: return "gearshape"
            case .trash: return "trash"
            case .lock: return "lock"
            case .wifi: return "wifi"
            case .battery: return "battery.100"
            case .keyboard: return "keyboard"
            case .bell: return "bell"
            case .search: return "magnifyingglass"
            case .terminal: return "terminal"
            case .download: return "arrow.down.to.line"
            case .upload: return "arrow.up.to.line"
            case .close: return "xmark"
            case .maximize: return "arrow.up.left.and.arrow.down.right"
            case .minimize: return "arrow.down.right.and.arrow.up.left"
            case .chevronRight: return "chevron.right"
            case .plus: return "plus"
            case .check: return "checkmark"
            case .power: return "power"
            case .moon: return "moon"
            case .sun: return "sun.max"
            case .shield: return "shield"
            case .key: return "key"
            case .calendar: return "calendar"
            case .clock: return "clock"
            case .link: return "link"
            case .copy: return "doc.on.doc"
            case .clipboard: return "doc.on.clipboard"
            case .appWindow: return "app.dashed"
            case .chartBar: return "chart.bar"
            case .cloud: return "cloud"
            case .plug: return "plug"
            case .bluetooth: return "bluetooth"
            case .volume: return "speaker.wave.2"
            case .camera: return "camera"
            case .mapPin: return "mappin"
            case .mail: return "envelope"
            case .shieldCheck: return "checkmark.shield"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .palette: return "paintpalette"
            case .list: return "list.bullet"
            }
        }

        /// Glyph name inside the selected library. Both families use this same name.
        func glyph(in family: Family) -> String { rawValue }
    }

    /// Bundled photographic wallpapers. They are generated locally by `scripts/generate_meadow.py`
    /// and `scripts/generate_ocean.py`; no external photo source or licence is involved.
    enum Wallpaper: String, CaseIterable {
        case meadow = "MeadowWallpaper"
        case ocean = "OceanWallpaper"

        var generatorScript: String {
            switch self {
            case .meadow: return "scripts/generate_meadow.py"
            case .ocean: return "scripts/generate_ocean.py"
            }
        }
    }

    static let families = Family.allCases
    static let wallpapers = Wallpaper.allCases.map(\.rawValue)

    /// SwiftUI image for a concept. Views can adopt this without knowing the icon family.
    static func image(_ icon: Icon) -> Image { Image(systemName: icon.sfSymbol) }

    /// Absolute path is intentionally not exposed: library assets are a build-time source, not
    /// runtime files. Callers that need the file use `Family.libraryPath` + `glyph(in:)`.
    static func libraryPath(for family: Family, icon: Icon) -> String {
        "\(family.libraryPath)/\(family == .tabler ? "outline" : "icons")/\(icon.glyph(in: family)).svg"
    }
}
