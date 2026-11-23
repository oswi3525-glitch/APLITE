import SwiftUI

/// Compact window switcher opened by the Window button on the dock. Like the Task Manager it is
/// drawn in SwiftUI and hit-tested in DesktopModel: the external display's scene receives no touches.
extension DesktopModel {
    var windowListRect: CGRect {
        WindowListMath.panelRect(screen: screenSize, taskbarTop: taskbarTop, count: windows.count)
    }

    func windowListRowRect(_ i: Int) -> CGRect {
        WindowListMath.rowRect(in: windowListRect, index: i)
    }

    func windowListCloseRect(_ i: Int) -> CGRect {
        WindowListMath.closeRect(in: windowListRowRect(i))
    }

    var windowListTileRect: CGRect { WindowListMath.footerRects(in: windowListRect).tile }

    var windowListDesktopRect: CGRect { WindowListMath.footerRects(in: windowListRect).desktop }

    func clickWindowList(at p: CGPoint) {
        guard windowListRect.contains(p) else {
            showWindowList = false
            // Let a dock button act on this same click, except the Window button itself (that would reopen).
            if p.y >= taskbarHitTop, !windowListButtonRect.contains(p) { clickTaskbar(p) }
            return
        }
        let rows = WindowListMath.visibleRows(count: windows.count)
        for i in windows.indices.prefix(rows) where windowListCloseRect(i).contains(p) {
            close(windows[i])
            return
        }
        for i in windows.indices.prefix(rows) where windowListRowRect(i).contains(p) {
            let w = windows[i]
            showWindowList = false
            focus(w)   // also restores a minimized window
            return
        }
        if windowListTileRect.contains(p) {
            WindowCoordinator.tile()
            showToast(String(localized: "Windows arranged in a grid"))
            showWindowList = false
            return
        }
        if windowListDesktopRect.contains(p) {
            toggleShowDesktop()
            showWindowList = false
        }
    }
}

struct WindowListView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var cursor: CursorModel

    var body: some View {
        let r = model.windowListRect
        let p = cursor.position
        let shown = WindowListMath.visibleRows(count: model.windows.count)
        ZStack(alignment: .topLeading) {
            HStack(spacing: 9) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Windows").font(.system(size: 14, weight: .semibold))
                    Text(verbatim: model.windows.count > shown
                         ? "\(shown) / \(model.windows.count) \(String(localized: "open"))"
                         : "\(model.windows.count) \(String(localized: "open"))")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.windows.isEmpty {
                    Text("No open windows").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(width: r.width - WindowListLayout.padding * 2, height: WindowListLayout.header)
            .offset(x: WindowListLayout.padding, y: 0)

            ForEach(Array(model.windows.prefix(WindowListMath.visibleRows(count: model.windows.count))
                            .enumerated()), id: \.element.id) { i, w in
                    let row = model.windowListRowRect(i)
                    HStack(spacing: 10) {
                        if let icon = w.icon {
                            Image(uiImage: icon).resizable()
                                .frame(width: 26, height: 26)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        } else {
                            Image(systemName: w.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 26, height: 26)
                                .foregroundStyle(Color.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(w.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                            Text(w.isMinimized ? String(localized: "Minimized")
                                 : w.workspace == model.workspace ? String(localized: "Running")
                                 : String(localized: "Other workspace"))
                                .font(.system(size: 10))
                                .foregroundStyle(w.isMinimized ? .secondary : Color.accentColor)
                        }
                        Spacer(minLength: 0)
                        if model.windowListCloseRect(i).contains(p) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(APLiteColors.red)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(width: row.width, height: row.height)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(row.contains(p) ? Color.white.opacity(0.12) : Color.white.opacity(0.04)))
                    .offset(x: row.minX - r.minX, y: row.minY - r.minY)
            }

            footerButton(String(localized: "Tile"), rect: model.windowListTileRect, panel: r, p: p)
            footerButton(String(localized: "Show desktop"), rect: model.windowListDesktopRect, panel: r, p: p)
        }
        .frame(width: r.width, height: r.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .offset(x: r.minX, y: r.minY)
    }

    private func footerButton(_ title: String, rect: CGRect, panel: CGRect, p: CGPoint) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .frame(width: rect.width, height: rect.height)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(rect.contains(p) ? 0.18 : 0.08)))
            .offset(x: rect.minX - panel.minX, y: rect.minY - panel.minY)
    }
}
