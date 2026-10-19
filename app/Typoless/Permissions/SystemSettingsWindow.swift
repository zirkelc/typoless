import AppKit
import CoreGraphics

/**
 Where the System Settings window is on screen.

 Both permissions are granted in System Settings, which means the useful half
 of setup happens in an application this one does not control and cannot see
 into. It can see where the window is, though, and that is enough to put the
 instructions against the list they are about to be used on.

 Asked of the window server rather than of the accessibility API, which is the
 whole point: the accessibility API is the permission being granted, so a
 helper that needed it could only appear once it was no longer needed. The
 window list needs nothing. It withholds window titles from an app without
 screen recording, and titles are not wanted here, only the frame.
 */
enum SystemSettingsWindow {
    /** The same application under both of the names it has had. */
    static let ownerNames: Set<String> = ["System Settings", "System Preferences"]

    /** Smaller than this is a sheet, a tooltip or a shadow, not the window. */
    private static let smallestWindow = CGSize(width: 320, height: 240)

    /** The window as the window server has it, with the origin at the top left. */
    static func currentFrame() -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        return frame(in: infos)
    }

    /**
     The largest ordinary window the application owns.

     Largest, because System Settings puts more than one window on the list at
     once: a sheet, and on some releases an offscreen helper the same size as
     nothing. Layer zero keeps out the panels that float above it.
     */
    static func frame(in infos: [[String: Any]]) -> CGRect? {
        let windows = infos.compactMap { info -> CGRect? in
            guard
                let owner = info[kCGWindowOwnerName as String] as? String,
                ownerNames.contains(owner),
                (info[kCGWindowLayer as String] as? Int) == 0,
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                rect.width >= smallestWindow.width,
                rect.height >= smallestWindow.height
            else {
                return nil
            }

            return rect
        }

        return windows.max { $0.width * $0.height < $1.width * $1.height }
    }

    /**
     The same frame as AppKit counts, which is from the bottom of the main
     screen upwards rather than from the top of it downwards.
     */
    static func appKitFrame(from frame: CGRect, mainScreenTop: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX,
            y: mainScreenTop - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    /** The top edge of the screen the window server measures everything from. */
    static var mainScreenTop: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    /**
     Where the helper sits against that window.

     Along the bottom edge and inside it, which is the one part of a settings
     pane that holds nothing: the list being dragged into is above, and the
     window's own buttons are at the top. Centred rather than aligned to the
     list, since this app is told where the window is and not what is in it.
     */
    static func helperFrame(against settings: CGRect, size: CGSize) -> CGRect {
        let width = min(size.width, settings.width - 24)

        return CGRect(
            x: settings.midX - width / 2,
            y: settings.minY + 14,
            width: width,
            height: size.height
        )
    }
}
