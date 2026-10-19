import CoreGraphics
import Foundation
import Testing
@testable import Typoless

/**
 Finding the window the setup helper attaches itself to.

 The helper is placed over another application's window, which is the one
 arrangement that goes wrong silently: a frame that is off by a screen puts the
 instructions somewhere nobody is looking, and the user sees an app that asks
 for a permission and then says nothing about how to grant it.
 */
struct SystemSettingsWindowTests {
    private static func window(
        owner: String,
        layer: Int = 0,
        x: CGFloat = 0,
        y: CGFloat = 0,
        width: CGFloat = 700,
        height: CGFloat = 900
    ) -> [String: Any] {
        [
            kCGWindowOwnerName as String: owner,
            kCGWindowLayer as String: layer,
            kCGWindowBounds as String: ["X": x, "Y": y, "Width": width, "Height": height],
        ]
    }

    @Test
    func `the settings window is found among everything else on screen`() {
        // Arrange
        let windows = [
            Self.window(owner: "Finder"),
            Self.window(owner: "System Settings", x: 100, y: 50),
            Self.window(owner: "Safari", x: 400, y: 400),
        ]

        // Act
        let frame = SystemSettingsWindow.frame(in: windows)

        // Assert
        #expect(frame == CGRect(x: 100, y: 50, width: 700, height: 900))
    }

    /** The window is the largest one it owns; the small ones are sheets and shadows. */
    @Test
    func `the largest of the applications own windows wins`() {
        // Arrange
        let windows = [
            Self.window(owner: "System Settings", x: 0, y: 0, width: 400, height: 300),
            Self.window(owner: "System Settings", x: 10, y: 20, width: 700, height: 900),
        ]

        // Act
        let frame = SystemSettingsWindow.frame(in: windows)

        // Assert
        #expect(frame == CGRect(x: 10, y: 20, width: 700, height: 900))
    }

    @Test
    func `panels floating above the window are not the window`() {
        // Arrange
        let windows = [Self.window(owner: "System Settings", layer: 3)]

        // Act
        let frame = SystemSettingsWindow.frame(in: windows)

        // Assert
        #expect(frame == nil)
    }

    @Test
    func `anything too small to hold a list is ignored`() {
        // Arrange
        let windows = [Self.window(owner: "System Settings", width: 200, height: 100)]

        // Act
        let frame = SystemSettingsWindow.frame(in: windows)

        // Assert
        #expect(frame == nil)
    }

    @Test
    func `nothing is found when settings is closed`() {
        // Arrange
        let windows = [Self.window(owner: "Finder"), Self.window(owner: "Mail")]

        // Act
        let frame = SystemSettingsWindow.frame(in: windows)

        // Assert
        #expect(frame == nil)
    }

    /**
     The window server counts down from the top of the main screen and AppKit
     counts up from the bottom of it. A helper placed with one set of numbers
     in the other coordinate system lands as far from the window as the window
     is from the middle of the screen, which on a tall screen is off it.
     */
    @Test
    func `the frame is turned the right way up for AppKit`() {
        // Arrange
        let fromWindowServer = CGRect(x: 100, y: 50, width: 700, height: 900)

        // Act
        let frame = SystemSettingsWindow.appKitFrame(from: fromWindowServer, mainScreenTop: 1200)

        // Assert
        #expect(frame == CGRect(x: 100, y: 250, width: 700, height: 900))
    }

    @Test
    func `the helper sits along the bottom of the window, in the middle`() {
        // Arrange
        let settings = CGRect(x: 100, y: 200, width: 700, height: 900)

        // Act
        let frame = SystemSettingsWindow.helperFrame(against: settings, size: CGSize(width: 470, height: 104))

        // Assert
        #expect(frame.midX == settings.midX)
        #expect(frame.minY == 214)
        #expect(frame.width == 470)
    }

    /** A window narrower than the helper would have it hanging over both edges. */
    @Test
    func `the helper never grows wider than the window it is on`() {
        // Arrange
        let settings = CGRect(x: 0, y: 0, width: 400, height: 500)

        // Act
        let frame = SystemSettingsWindow.helperFrame(against: settings, size: CGSize(width: 470, height: 104))

        // Assert
        #expect(frame.width == 376)
        #expect(frame.minX >= settings.minX)
        #expect(frame.maxX <= settings.maxX)
    }
}
