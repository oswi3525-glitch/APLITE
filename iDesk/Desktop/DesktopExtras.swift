import SwiftUI

// MARK: - Window layouts

/// The layouts offered when a window is dragged to the top edge of the screen. Each is a row of zones; dropping the
/// window on a zone puts it there.
enum TileLayouts {
    static let all: [[DesktopModel.Snap]] = [
        [.left, .right],
        [.leftTwoThirds, .rightThird],
        [.leftThird, .rightTwoThirds],
        [.leftThird, .centerThird, .rightThird],
        [.topLeft, .topRight, .bottomLeft, .bottomRight],
        [.maximize],
    ]
    static let cell = CGSize(width: 92, height: 56)
    static let gap: CGFloat = 10
    static let padding: CGFloat = 12
    static let title: CGFloat = 22

    /// The zone that fills the rest of the screen next to a window put in `s` (none for quarters and the middle).
    static func complement(of s: DesktopModel.Snap) -> DesktopModel.Snap? {
        switch s {
        case .left: return .right
        case .right: return .left
        case .leftThird: return .rightTwoThirds
        case .rightThird: return .leftTwoThirds
        case .leftTwoThirds: return .rightThird
        case .rightTwoThirds: return .leftThird
        default: return nil
        }
    }
}

struct TileZone: Equatable {
    let layout: Int
    let zone: Int
    var snap: DesktopModel.Snap { TileLayouts.all[layout][zone] }
}

/// After a window is put in half (or a third) of the screen: the other windows, to fill the rest with one click.
struct FillSuggestion {
    let zone: DesktopModel.Snap
    let ids: [UUID]
}

struct CaptureState {
    var start: CGPoint?
    var rect: CGRect?
}

struct ScreenshotPreview {
    let image: UIImage
    let path: String          // in Files
}

struct StickyNote: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var x: Double
    var y: Double
    var width: Double = 240
    var height: Double = 210
    var color = 0

    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    static let header: CGFloat = 26
    static let colors: [(Color, Color)] = [   // paper, header
        (Color(red: 1.0, green: 0.93, blue: 0.55), Color(red: 0.98, green: 0.85, blue: 0.35)),
        (Color(red: 0.75, green: 0.95, blue: 0.7), Color(red: 0.58, green: 0.87, blue: 0.52)),
        (Color(red: 1.0, green: 0.78, blue: 0.84), Color(red: 0.98, green: 0.64, blue: 0.74)),
        (Color(red: 0.72, green: 0.87, blue: 1.0), Color(red: 0.55, green: 0.76, blue: 0.98)),
        (Color(red: 0.86, green: 0.78, blue: 1.0), Color(red: 0.75, green: 0.64, blue: 0.98)),
    ]
    static let colorNames: [String.LocalizationValue] = ["Yellow", "Green", "Pink", "Blue", "Purple"]

    private static let key = "iDesk.stickies"
    static func load() -> [StickyNote] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([StickyNote].self, from: data)) ?? []
    }
    static func save(_ notes: [StickyNote]) {
        if let data = try? JSONEncoder().encode(notes) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// MARK: - Views

struct TilePickerView: View {
    @ObservedObject var model: DesktopModel

    var body: some View {
        let r = model.tilePickerRect
        ZStack(alignment: .topLeading) {
            Text("Drop on a zone to arrange the window")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .offset(x: TileLayouts.padding, y: 6)
            ForEach(TileLayouts.all.indices, id: \.self) { li in
                let cell = model.tileCellRect(li)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.25))
                        .frame(width: cell.width, height: cell.height)
                    ForEach(TileLayouts.all[li].indices, id: \.self) { zi in
                        let z = model.tileZoneRect(li, zi)
                        let on = model.tileHover == TileZone(layout: li, zone: zi)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(on ? Color.accentColor : Color.white.opacity(0.28))
                            .frame(width: z.width, height: z.height)
                            .offset(x: z.minX - cell.minX, y: z.minY - cell.minY)
                    }
                }
                .offset(x: cell.minX - r.minX, y: cell.minY - r.minY)
            }
        }
        .frame(width: r.width, height: r.height, alignment: .topLeading)
        .floatingPanel(cornerRadius: 14, shadow: 16)
        .offset(x: r.minX, y: r.minY)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct FillSuggestionView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var cursor: CursorModel
    let suggestion: FillSuggestion

    var body: some View {
        let area = model.fillArea(suggestion)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.35))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(width: area.width, height: area.height)
            Text("Choose a window for this side · Esc: no thanks")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                .frame(width: area.width, height: 36)
                .offset(y: 14)
            ForEach(Array(suggestion.ids.enumerated()), id: \.element) { i, id in
                if let w = model.windows.first(where: { $0.id == id }) {
                    let t = model.fillCardRect(i, of: suggestion)
                    let hovered = t.contains(cursor.position)
                    VStack(spacing: 8) {
                        Group {
                            if let image = model.fillThumbnails[id] {
                                Image(uiImage: image).resizable().scaledToFit()
                            } else {
                                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08))
                                    .overlay(Image(systemName: w.symbol).font(.system(size: 28)).foregroundStyle(.secondary))
                            }
                        }
                        .frame(width: t.width - 20, height: t.height - 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        HStack(spacing: 6) {
                            if let icon = w.icon { Image(uiImage: icon).resizable().frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: 4)) }
                            Text(verbatim: w.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        }
                    }
                    .padding(10)
                    .frame(width: t.width, height: t.height)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hovered ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(hovered ? Color.accentColor : Color.white.opacity(0.15), lineWidth: hovered ? 2 : 1))
                    .offset(x: t.minX - area.minX, y: t.minY - area.minY)
                }
            }
        }
        .frame(width: area.width, height: area.height, alignment: .topLeading)
        .offset(x: area.minX, y: area.minY)
    }
}

/// Screenshot of an area: the screen dims except the part being selected.
struct CaptureOverlayView: View {
    let state: CaptureState
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                if let r = state.rect { p.addRect(r) }
            }
            .fill(Color.black.opacity(0.4), style: FillStyle(eoFill: true))
            if let r = state.rect, r.width > 1 {
                Rectangle().stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                Text(verbatim: "\(Int(r.width)) × \(Int(r.height))")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .offset(x: r.maxX + 8 > size.width - 90 ? r.maxX - 90 : r.maxX + 8, y: min(r.maxY + 8, size.height - 30))
            } else {
                Text("Drag to capture an area · click a window to capture it · Esc to cancel")
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .frame(width: size.width)
                    .offset(y: 28)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

struct ScreenshotPreviewView: View {
    let preview: ScreenshotPreview
    let rect: CGRect
    let hovered: Bool

    var body: some View {
        Image(uiImage: preview.image).resizable().scaledToFit()
            .frame(width: rect.width, height: rect.height)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(hovered ? 0.9 : 0.5), lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 14, y: 4)
            .scaleEffect(hovered ? 1.03 : 1)
            .offset(x: rect.minX, y: rect.minY)
            .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}

struct StickiesView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var cursor: CursorModel
    /// true: only the note being typed in (drawn above the windows); false: the others (under them).
    var floating = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.stickies.filter { ($0.id == model.floatingSticky) == floating }) { note in
                let f = note.frame
                let colors = StickyNote.colors[note.color % StickyNote.colors.count]
                let editing = model.editingSticky == note.id
                let close = model.stickyCloseRect(note)
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.black.opacity(close.contains(cursor.position) ? 0.8 : 0.4))
                            .frame(width: close.width, height: close.height)
                    }
                    .frame(height: StickyNote.header)
                    .background(colors.1)
                    Group {
                        if note.text.isEmpty && !editing {
                            Text("Click and type").foregroundStyle(Color.black.opacity(0.35))
                        } else {
                            Text(verbatim: note.text) + (editing ? Text(verbatim: "|").foregroundColor(.accentColor) : Text(verbatim: ""))
                        }
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(10)
                }
                .frame(width: f.width, height: f.height)
                .background(colors.0)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(editing ? Color.accentColor : Color.black.opacity(0.1), lineWidth: editing ? 2 : 1))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                .offset(x: f.minX, y: f.minY)
            }
        }
    }
}
