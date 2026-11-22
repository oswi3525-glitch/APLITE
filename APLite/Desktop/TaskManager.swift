import SwiftUI

/// A small task manager for the desktop: what is open, how much memory the host is using, and
/// controls to close or minimize windows. It is drawn as a panel and hit-tested by DesktopModel
/// because the external display receives no real touches.
enum TaskManagerLayout {
    static let width: CGFloat = 420
    static let row: CGFloat = 54
    static let header: CGFloat = 64
    static let footer: CGFloat = 52
}

extension DesktopModel {
    var taskManagerRect: CGRect {
        let h = min(560, max(220, TaskManagerLayout.header + TaskManagerLayout.footer
                             + CGFloat(windows.count) * TaskManagerLayout.row + 16))
        return CGRect(x: max(12, screenSize.width - TaskManagerLayout.width - 16),
                      y: 56, width: TaskManagerLayout.width, height: h)
    }

    func taskManagerRowRect(_ i: Int) -> CGRect {
        let r = taskManagerRect
        return CGRect(x: r.minX + 12, y: r.minY + TaskManagerLayout.header + CGFloat(i) * TaskManagerLayout.row,
                      width: r.width - 24, height: TaskManagerLayout.row - 6)
    }

    func taskManagerCloseRect(_ i: Int) -> CGRect {
        let row = taskManagerRowRect(i)
        return CGRect(x: row.maxX - 38, y: row.minY + 9, width: 30, height: 30)
    }

    private var taskManagerFooterWidth: CGFloat { (taskManagerRect.width - 52) / 3 }

    var taskManagerTileRect: CGRect {
        let r = taskManagerRect
        return CGRect(x: r.minX + 14, y: r.maxY - 44, width: taskManagerFooterWidth, height: 34)
    }

    var taskManagerMinimizeAllRect: CGRect {
        let r = taskManagerRect
        return CGRect(x: taskManagerTileRect.maxX + 12, y: r.maxY - 44, width: taskManagerFooterWidth, height: 34)
    }

    var taskManagerCloseAllRect: CGRect {
        let r = taskManagerRect
        return CGRect(x: taskManagerMinimizeAllRect.maxX + 12, y: r.maxY - 44, width: taskManagerFooterWidth, height: 34)
    }

    func clickTaskManager(at p: CGPoint) {
        guard taskManagerRect.contains(p) else { showTaskManager = false; return }
        for i in windows.indices where taskManagerCloseRect(i).contains(p) {
            close(windows[i])
            return
        }
        if taskManagerTileRect.contains(p) {
            WindowCoordinator.tile()
            showToast(String(localized: "Windows arranged in a grid"))
            return
        }
        if taskManagerMinimizeAllRect.contains(p) {
            windows.filter { $0.isShown }.forEach(minimize)
            showToast(String(localized: "All windows minimized"))
            return
        }
        if taskManagerCloseAllRect.contains(p) {
            let all = windows
            all.forEach(close)
            showToast(String(localized: "All windows closed"))
            showTaskManager = false
            return
        }
    }
}

/// The panel. Rows mirror `windows` exactly, so the close rects above always name the same window.
struct TaskManagerView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var cursor: CursorModel

    var body: some View {
        let r = model.taskManagerRect
        let p = cursor.position
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Task Manager").font(.system(size: 15, weight: .semibold))
                    Text(verbatim: "\(model.windows.count) \(String(localized: "windows")) · "
                         + MemoryStatus.format(MemoryManager.shared.used) + " \(String(localized: "in use")) · "
                         + String(localized: "peak") + " " + MemoryStatus.format(MemoryManager.shared.peak))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.windows.isEmpty {
                    Text(String(localized: "No open windows")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: TaskManagerLayout.header)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(model.windows.enumerated()), id: \.element.id) { i, w in
                        let row = model.taskManagerRowRect(i)
                        HStack(spacing: 10) {
                            if let icon = w.icon {
                                Image(uiImage: icon).resizable()
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            } else {
                                Image(systemName: w.symbol)
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(width: 28, height: 28)
                                    .foregroundStyle(Color.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(w.isMinimized ? String(localized: "Minimized")
                                     : String(localized: "Running"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(w.isMinimized ? .secondary : Color.accentColor)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(model.taskManagerCloseRect(i).contains(p) ? Color.red : Color.secondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(width: row.width, height: row.height)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(row.contains(p) ? Color.white.opacity(0.07) : Color.white.opacity(0.03)))
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: max(0, r.height - TaskManagerLayout.header - TaskManagerLayout.footer))

            ZStack(alignment: .topLeading) {
                let footerY = r.maxY - TaskManagerLayout.footer
                panelButton(String(localized: "Tile"),
                            rect: model.taskManagerTileRect.offsetBy(dx: -r.minX, dy: -footerY), p: p)
                panelButton(String(localized: "Minimize all"),
                            rect: model.taskManagerMinimizeAllRect.offsetBy(dx: -r.minX, dy: -footerY), p: p)
                panelButton(String(localized: "Close all"),
                            rect: model.taskManagerCloseAllRect.offsetBy(dx: -r.minX, dy: -footerY),
                            p: p, danger: true)
            }
            .frame(width: r.width, height: TaskManagerLayout.footer)
        }
        .frame(width: r.width, height: r.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .offset(x: r.minX, y: r.minY)
    }

    private func panelButton(_ title: String, rect: CGRect,
                             p: CGPoint, danger: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: rect.width, height: rect.height)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(danger ? Color.red.opacity(rect.contains(p) ? 0.32 : 0.18)
                             : Color.white.opacity(rect.contains(p) ? 0.18 : 0.08)))
            .offset(x: rect.minX, y: rect.minY)
    }
}
