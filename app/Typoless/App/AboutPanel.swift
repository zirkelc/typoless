import AppKit

/**
 The standard About window, with the app's own credits.

 The system panel rather than a window of our own: it already shows the icon,
 name, version, build and copyright, looks right in both appearances, and is
 what people expect "About" to open. The only part worth supplying is the
 credits.

 The credits link to the licence notices for every package the app ships.
 They are not decoration: the MIT, Apache and BSD licences all require their
 text to travel with the software, which it does, as a file in the bundle. The
 text itself is not put in the credits: at 149 KB it turned the panel's small
 scroll area into thousands of wrapped lines to scroll through.
 */
@MainActor
enum AboutPanel {
    static let website = URL(string: "https://typoless.app")!

    static func show() {
        /** An accessory app has to ask, or the panel opens behind everything. */
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits()])
    }

    private static func credits() -> NSAttributedString {
        let body = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.paragraphSpacing = 4

        let plain: [NSAttributedString.Key: Any] = [
            .font: body,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: centered,
        ]

        let text = NSMutableAttributedString()

        text.append(NSAttributedString(
            string: "Corrects spelling, punctuation, capitals and spacing on this Mac. Your text never leaves it.\n",
            attributes: plain
        ))

        var link = plain
        link[.link] = website
        text.append(NSAttributedString(string: (website.host() ?? website.absoluteString) + "\n", attributes: link))

        /**
         A missing file is a packaging mistake, and the panel says so rather
         than quietly shipping without the notices the licences ask for.
         */
        guard let notices = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") else {
            Log.app.error("Acknowledgements.txt is missing from the bundle")

            var warning = plain
            warning[.foregroundColor] = NSColor.systemRed
            text.append(NSAttributedString(string: "The open-source licences are missing from this build.", attributes: warning))

            return text
        }

        /** Opens in the Mac's default text app, where it can be read and searched. */
        link[.link] = notices
        text.append(NSAttributedString(string: "Open-source licences", attributes: link))

        return text
    }
}
