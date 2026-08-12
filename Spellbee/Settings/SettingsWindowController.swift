import AppKit
import SwiftUI

/**
 Hosts the settings window.

 An AppKit window with a real `NSToolbar` in its preference style, rather than a
 SwiftUI `TabView`. That style, icons above their labels across the top, is what
 a Mac settings window looks like, and SwiftUI only produces it inside a
 `Settings` scene, which this app cannot use: its windows are opened from a menu
 bar item, which is a direct call rather than an environment action that only
 exists inside a view hierarchy.

 The window resizes to each page as it is selected, which is the other half of
 the convention. A page of four checkboxes should not be as tall as the one
 listing applications.
 */
@MainActor
final class SettingsWindowController: NSObject, NSToolbarDelegate, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private var selected: SettingsTab = .general

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }

        /** An accessory app has to ask, or the window opens behind everything. */
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: selected.width, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.delegate = self

        let toolbar = NSToolbar(identifier: "Settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(selected.rawValue)

        window.toolbar = toolbar
        window.toolbarStyle = .preference

        self.window = window
        select(selected, animated: false)
        window.center()

        return window
    }

    private func select(_ tab: SettingsTab, animated: Bool) {
        guard let window else { return }

        selected = tab
        window.title = tab.title
        window.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.rawValue)

        let hosting = NSHostingView(rootView: tab.view(model: model).frame(width: tab.width))
        hosting.layoutSubtreeIfNeeded()

        let size = NSSize(width: tab.width, height: hosting.fittingSize.height)
        window.contentView = hosting

        /**
         Grown from the top edge rather than the centre, so the title bar stays
         put and only the bottom of the window moves.
         */
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(
            x: window.frame.origin.x,
            y: window.frame.maxY - frame.height
        )

        window.setFrame(frame, display: true, animate: animated)
    }

    @objc private func toolbarItemSelected(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(rawValue: sender.itemIdentifier.rawValue) else { return }
        select(tab, animated: true)
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    /** Every item is a page, so every item shows as selected when it is. */
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = SettingsTab(rawValue: identifier.rawValue) else { return nil }

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(toolbarItemSelected)

        return item
    }
}
