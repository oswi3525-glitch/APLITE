import Foundation
import CoreGraphics

/// Pure geometry and key data for APLite's on-screen keyboard. No UIKit / WebKit here so the layout
/// can be unit tested and shared by the view (drawing) and DesktopModel (hit testing on a display
/// that receives no touches).
enum KeyboardLayout {
    enum Action: Equatable {
        case text(String)
        /// A named key and the keyCode used by WebInput.key / PhoneWindow.handle.
        case special(String, Int)
        case backspace, enter, tab, escape
        case shift, capsLock, symbols, hide
        case selectAll, copy, paste
    }

    struct Key: Equatable, Identifiable {
        let id: String
        let label: String
        let units: Double
        let action: Action
        /// What a single Shift produces: an uppercase letter or the symbol above a digit.
        let shifted: String?

        var displayLabel: String { label }
    }

    static let columns: Double = 15
    static let padding: CGFloat = 12
    static let gap: CGFloat = 6
    static let header: CGFloat = 28
    static let maxWidth: CGFloat = 980

    private static func key(_ label: String, _ action: Action, units: Double = 1,
                            shifted: String? = nil, id: String? = nil) -> Key {
        Key(id: id ?? label, label: label, units: units, action: action, shifted: shifted)
    }

    /// QWERTY with a full function row: every key a desktop keyboard has that APLite can Forward.
    static let letterRows: [[Key]] = [
        [key("esc", .escape, units: 1.5, id: "esc"),
         key("1", .text("1"), shifted: "!"), key("2", .text("2"), shifted: "@"),
         key("3", .text("3"), shifted: "#"), key("4", .text("4"), shifted: "$"),
         key("5", .text("5"), shifted: "%"), key("6", .text("6"), shifted: "^"),
         key("7", .text("7"), shifted: "&"), key("8", .text("8"), shifted: "*"),
         key("9", .text("9"), shifted: "("), key("0", .text("0"), shifted: ")"),
         key("-", .text("-"), shifted: "_"), key("=", .text("="), shifted: "+"),
         key("⌫", .backspace, units: 1.5, id: "backspace")],

        [key("tab", .tab, units: 1.5, id: "tab"),
         key("q", .text("q"), shifted: "Q"), key("w", .text("w"), shifted: "W"),
         key("e", .text("e"), shifted: "E"), key("r", .text("r"), shifted: "R"),
         key("t", .text("t"), shifted: "T"), key("y", .text("y"), shifted: "Y"),
         key("u", .text("u"), shifted: "U"), key("i", .text("i"), shifted: "I"),
         key("o", .text("o"), shifted: "O"), key("p", .text("p"), shifted: "P"),
         key("[", .text("["), shifted: "{"), key("]", .text("]"), shifted: "}"),
         key("\\", .text("\\"), shifted: "|", units: 1.5, id: "backslash")],

        [key("caps", .capsLock, units: 1.75, id: "caps"),
         key("a", .text("a"), shifted: "A"), key("s", .text("s"), shifted: "S"),
         key("d", .text("d"), shifted: "D"), key("f", .text("f"), shifted: "F"),
         key("g", .text("g"), shifted: "G"), key("h", .text("h"), shifted: "H"),
         key("j", .text("j"), shifted: "J"), key("k", .text("k"), shifted: "K"),
         key("l", .text("l"), shifted: "L"), key(";", .text(";"), shifted: ":"),
         key("'", .text("'"), shifted: "\""),
         key("enter", .enter, units: 2.25, id: "enter")],

        [key("shift", .shift, units: 2.25, id: "shiftLeft"),
         key("z", .text("z"), shifted: "Z"), key("x", .text("x"), shifted: "X"),
         key("c", .text("c"), shifted: "C"), key("v", .text("v"), shifted: "V"),
         key("b", .text("b"), shifted: "B"), key("n", .text("n"), shifted: "N"),
         key("m", .text("m"), shifted: "M"), key(",", .text(","), shifted: "<"),
         key(".", .text("."), shifted: ">"), key("/", .text("/"), shifted: "?"),
         key("shift", .shift, units: 2.75, id: "shiftRight")],

        [key("ctrl", .special("Control", 17), units: 1.25, id: "ctrl"),
         key("alt", .special("Alt", 18), units: 1.25, id: "alt"),
         key("⌘", .special("Meta", 91), units: 1.25, id: "meta"),
         key("space", .text(" "), units: 6.25, id: "space"),
         key("←", .special("ArrowLeft", 37), id: "left"),
         key("↓", .special("ArrowDown", 40), id: "down"),
         key("↑", .special("ArrowUp", 38), id: "up"),
         key("→", .special("ArrowRight", 39), id: "right"),
         key("hide", .hide, id: "hide")],

        [key("home", .special("Home", 36), id: "home"),
         key("end", .special("End", 35), id: "end"),
         key("pgup", .special("PageUp", 33), id: "pageUp"),
         key("pgdn", .special("PageDown", 34), id: "pageDown"),
         key("del", .special("Delete", 46), id: "delete"),
         key("sel all", .selectAll, id: "selectAll"),
         key("copy", .copy, id: "copy"),
         key("paste", .paste, id: "paste"),
         key("123", .symbols, id: "symbols")],
    ]

    /// The second layer: punctuation and symbols, reachable from the 123 key (or Shift on letters).
    static let symbolRows: [[Key]] = [
        letterRows[0],
        [key("tab", .tab, units: 1.5, id: "tab"),
         key("!", .text("!")), key("@", .text("@")), key("#", .text("#")),
         key("$", .text("$")), key("%", .text("%")), key("^", .text("^")),
         key("&", .text("&")), key("*", .text("*")), key("(", .text("(")),
         key(")", .text(")")), key("_", .text("_")), key("+", .text("+")),
         key("⌫", .backspace, units: 1.5, id: "backspace")],
        [key("caps", .capsLock, units: 1.75, id: "caps"),
         key("{", .text("{")), key("}", .text("}")), key("[", .text("[")),
         key("]", .text("]")), key(":", .text(":")), key(";", .text(";")),
         key("\"", .text("\"")), key("'", .text("'")), key("|", .text("|")),
         key("\\", .text("\\")), key("~", .text("~")),
         key("enter", .enter, units: 2.25, id: "enter")],
        [key("shift", .shift, units: 2.25, id: "shiftLeft"),
         key("`", .text("`")), key("<", .text("<")), key(">", .text(">")),
         key(",", .text(",")), key(".", .text(".")), key("?", .text("?")),
         key("/", .text("/")), key("=", .text("=")), key("-", .text("-")),
         key("€", .text("€")),
         key("shift", .shift, units: 2.75, id: "shiftRight")],
        letterRows[4],
        [key("home", .special("Home", 36), id: "home"),
         key("end", .special("End", 35), id: "end"),
         key("pgup", .special("PageUp", 33), id: "pageUp"),
         key("pgdn", .special("PageDown", 34), id: "pageDown"),
         key("del", .special("Delete", 46), id: "delete"),
         key("sel all", .selectAll, id: "selectAll"),
         key("copy", .copy, id: "copy"),
         key("paste", .paste, id: "paste"),
         key("abc", .symbols, id: "letters")],
    ]

    static func rows(symbols: Bool) -> [[Key]] { symbols ? symbolRows : letterRows }

    // MARK: Geometry

    static func unitWidth(for panelWidth: CGFloat) -> CGFloat {
        max(22, (panelWidth - 2 * padding - gap * CGFloat(columns - 1)) / CGFloat(columns))
    }

    static func keyHeight(forUnit unit: CGFloat) -> CGFloat { min(56, max(32, unit)) }

    /// Centred on the screen, anchored just above the dock. `scale` comes from the keyboard-size setting.
    static func panelRect(screen: CGSize, taskbarTop: CGFloat, scale: CGFloat = 1) -> CGRect {
        let width = min(maxWidth, screen.width - 24) * min(1.4, max(0.6, scale))
        let unit = unitWidth(for: width)
        let height = padding * 2 + header + CGFloat(rows(symbols: false).count) * (keyHeight(forUnit: unit) + gap) - gap
        return CGRect(x: max(8, (screen.width - width) / 2),
                      y: max(8, taskbarTop - height - 12),
                      width: width, height: height)
    }

    static func keyRects(in panel: CGRect, symbols: Bool) -> [(key: Key, rect: CGRect)] {
        let unit = unitWidth(for: panel.width)
        let height = keyHeight(forUnit: unit)
        var result: [(key: Key, rect: CGRect)] = []
        var y = panel.minY + padding + header
        for row in rows(symbols: symbols) {
            let rowWidth = row.reduce(CGFloat(0)) { $0 + width(for: $1.units, unit: unit) }
                + gap * CGFloat(max(0, row.count - 1))
            var x = panel.minX + (panel.width - rowWidth) / 2
            for key in row {
                let w = width(for: key.units, unit: unit)
                result.append((key, CGRect(x: x, y: y, width: w, height: height)))
                x += w + gap
            }
            y += height + gap
        }
        return result
    }

    static func key(at point: CGPoint, in panel: CGRect, symbols: Bool) -> Key? {
        keyRects(in: panel, symbols: symbols).first { $0.rect.contains(point) }?.key
    }

    private static func width(for units: Double, unit: CGFloat) -> CGFloat {
        unit * CGFloat(units) + gap * CGFloat(max(0, units - 1))
    }
}
