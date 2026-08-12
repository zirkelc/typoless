import AppKit

enum ScreenGeometry {
    /**
     Converts a rect expressed in top-left origin screen coordinates to Cocoa's
     bottom-left origin.

     The accessibility APIs report frames in the top-left system used by Quartz
     display services, while windows are positioned in Cocoa coordinates. The
     flip is always relative to the *primary* screen (the one at index zero),
     not the screen the rect happens to land on, because that screen's origin is
     what both coordinate systems share.
     */
    static func cocoaRect(fromTopLeft rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        return CGRect(
            x: rect.minX,
            y: primary.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
