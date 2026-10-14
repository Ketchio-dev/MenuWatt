import AppKit
import CoreGraphics

struct MenuBarHoverWindow {
    let frame: NSRect
    let level: Int
}

/// Screen/window coordinates use AppKit's bottom-left origin. No titles or
/// images are read; WindowServer bounds and levels are enough for this policy.
struct MenuBarHoverSnapshot {
    var location: NSPoint
    var screenFrames: [NSRect]
    var windows: [MenuBarHoverWindow]
    var mouseButtonsDown = false

    var menuBarFrames: [NSRect] {
        windows.compactMap { window in
            guard window.level == NSWindow.Level.mainMenu.rawValue,
                  window.frame.height > 0, window.frame.height <= 80 else { return nil }
            guard screenFrames.contains(where: { screen in
                abs(window.frame.maxY - screen.maxY) <= 2
                    && abs(window.frame.minX - screen.minX) <= 2
                    && abs(window.frame.width - screen.width) <= 2
            }) else { return nil }
            return window.frame
        }
    }

    var isInMenuBar: Bool {
        menuBarFrames.contains { $0.contains(location) }
    }

    var isInteracting: Bool {
        if mouseButtonsDown { return true }
        let bars = menuBarFrames
        return windows.contains { window in
            // Native menus can extend below the bar and into submenus. Keep
            // them alive until dismissed, rather than tracking only the cursor.
            if window.level == NSWindow.Level.popUpMenu.rawValue {
                return window.frame.width > 0 && window.frame.height > 0
            }
            // Common status-item popovers use floating/modal panels. Only
            // protect panels attached to a visible bar, not unrelated windows.
            guard window.level == NSWindow.Level.floating.rawValue
                    || window.level == NSWindow.Level.modalPanel.rawValue else { return false }
            return bars.contains { bar in
                window.frame.height > bar.height
                    && window.frame.maxY <= bar.maxY
                    && window.frame.maxY >= bar.minY - 12
                    && window.frame.maxX > bar.minX && window.frame.minX < bar.maxX
            }
        }
    }

    @MainActor
    static func live() -> Self {
        let screens = NSScreen.screens
        // CG window coordinates are top-left based, relative to the primary
        // display. NSScreen.screens.first stays the coordinate origin even if
        // another screen is main/key. This also handles negative screen origins.
        let primaryTop = screens.first?.frame.maxY ?? 0
        let metadata = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []
        let windows: [MenuBarHoverWindow] = metadata.compactMap { record in
            guard let level = record[kCGWindowLayer as String] as? Int,
                  let bounds = record[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return MenuBarHoverWindow(
                frame: NSRect(x: rect.minX, y: primaryTop - rect.maxY,
                              width: rect.width, height: rect.height),
                level: level
            )
        }
        return Self(location: NSEvent.mouseLocation, screenFrames: screens.map(\.frame),
                    windows: windows, mouseButtonsDown: NSEvent.pressedMouseButtons != 0)
    }
}
