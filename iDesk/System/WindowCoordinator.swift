import Foundation
import SwiftUI

/// Internal window API for APLite modules. It does not replace DeskWindow's hit testing or the
/// existing drag/resize code; it gives Settings, Power and other modules a stable, one-way façade.
enum WindowCoordinator {
    /// Visible, non-fullscreen windows in stacking order.
    static func managed() -> [DeskWindow] {
        DesktopModel.shared.windows.filter { $0.isShown && !$0.isFullscreen }
    }

    /// Tile visible windows into a balanced grid without closing or reloading any of them.
    static func tile() {
        let model = DesktopModel.shared
        let windows = managed()
        let frames = WindowLayout.grid(count: windows.count, in: model.desktopArea)
        APLiteAnimation.perform(APLiteAnimation.gentle) {
            for (window, frame) in zip(windows, frames) {
                window.isMaximized = false
                window.isSnapped = false
                window.snap = nil
                window.frame = WindowLayout.clamp(frame, to: model.desktopArea)
            }
            model.objectWillChange.send()
        }
    }

    /// Save/restore pure state. Used by Power Manager and available to Settings.
    static func capture() -> [WindowSnapshot] {
        DesktopModel.shared.windows.map {
            WindowSnapshot(id: $0.id, frame: $0.frame, minimized: $0.isMinimized,
                           maximized: $0.isMaximized, keepOnTop: $0.keepOnTop)
        }
    }

    static func restore(_ snapshots: [WindowSnapshot]) {
        let model = DesktopModel.shared
        let area = model.desktopArea
        APLiteAnimation.perform(APLiteAnimation.gentle) {
            for snapshot in snapshots {
                guard let window = model.windows.first(where: { $0.id == snapshot.id }) else { continue }
                window.frame = WindowLayout.clamp(snapshot.frame, to: area)
                window.isMinimized = snapshot.minimized
                window.isMaximized = snapshot.maximized
                window.keepOnTop = snapshot.keepOnTop
            }
            model.objectWillChange.send()
        }
    }

    static func bringToFront(_ id: UUID) {
        guard let window = DesktopModel.shared.windows.first(where: { $0.id == id }) else { return }
        DesktopModel.shared.focus(window)
    }

    /// Reduced-motion aware: callers do not need to know which animation system is active.
    static func animate(_ changes: @escaping () -> Void) {
        APLiteAnimation.perform(APLiteAnimation.gentle, changes)
    }
}
