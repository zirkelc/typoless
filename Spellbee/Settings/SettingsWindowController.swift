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

    /**
     One hosting view per page, built once and kept.

     Rebuilding it on every click threw away the whole SwiftUI graph and laid it
     out again from nothing, which is most of what made switching tabs feel
     slow. Six pages of settings are cheap to keep, and a page that is off
     screen still tracks the preferences it observes, so none of them go stale.
     */
    private var pages: [SettingsTab: NSView] = [:]

    /**
     Whether a height change should animate.

     False while a page is being put on screen, because `setFrame(animate:)`
     blocks the main thread for as long as the animation runs, and AppKit scales
     that with the distance: a third of a second for the drop from the tallest
     page to the shortest. Paid on every click, that is the lag. Growth that
     happens later, such as a language opening to show its rules, still animates
     since nothing is waiting on it.
     */
    private var animatesResize = false

    init(model: AppModel) {
        self.model = model
    }

    /** A named tab is for callers sending the user to one specific setting. */
    func show(_ tab: SettingsTab? = nil) {
        if window == nil {
            window = makeWindow()
        }

        if let tab, tab != selected {
            select(tab)
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
        select(selected)
        window.center()

        return window
    }

    private func select(_ tab: SettingsTab) {
        guard let window else { return }

        selected = tab
        window.title = tab.title
        window.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.rawValue)

        let page = pages[tab] ?? makePage(for: tab)
        pages[tab] = page

        animatesResize = false
        window.contentView = page
        resize(toContentHeight: page.fittingSize.height, animated: false)

        /** Once the switch has settled, later growth is free to animate again. */
        Task { @MainActor in animatesResize = true }
    }

    private func makePage(for tab: SettingsTab) -> NSView {
        /**
         The page reports its own height rather than being measured once.

         A page whose content can grow, such as a language opening to show its
         rules, would otherwise be clipped by a window sized before it did.
         */
        let root = tab.view(model: model)
            .frame(width: tab.width)
            .background(
                GeometryReader { [weak self] proxy in
                    Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in
                        MainActor.assumeIsolated {
                            guard let self else { return }

                            /**
                             Kept pages stay laid out while off screen, so a
                             change on one of those must not resize the window
                             around whichever page is actually showing.
                             */
                            guard self.selected == tab else { return }

                            self.resize(toContentHeight: height, animated: self.animatesResize)
                        }
                    }
                }
            )

        let hosting = NSHostingView(rootView: root)
        hosting.layoutSubtreeIfNeeded()

        return hosting
    }

    /**
     Grows from the top edge rather than the centre, so the title bar stays put
     and only the bottom of the window moves.
     */
    private func resize(toContentHeight height: CGFloat, animated: Bool) {
        guard let window, height > 0 else { return }

        let size = NSSize(width: selected.width, height: height)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))

        guard abs(frame.height - window.frame.height) > 0.5 else { return }

        frame.origin = NSPoint(x: window.frame.origin.x, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animated)
    }

    /**
     Ends anything the window was in the middle of.

     The window is kept rather than released, so its pages are never told they
     disappeared and cannot clean up after themselves. A shortcut recorder left
     listening swallows every key press in the app until the next launch.
     */
    func windowWillClose(_ notification: Notification) {
        ShortcutListener.shared.stopAll()
    }

    @objc private func toolbarItemSelected(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(rawValue: sender.itemIdentifier.rawValue) else { return }
        select(tab)
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
