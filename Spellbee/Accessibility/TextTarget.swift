@preconcurrency import ApplicationServices
import AppKit

/** A text field the app has resolved and can read from and write back to. */
struct TextTarget {
    let element: AXUIElement

    /**
     The application the text belongs to.

     Kept so a correction can confirm the user has not moved on before it writes
     anything. Pasting is aimed at whatever is frontmost, not at a particular
     element, so writing into a field whose app is no longer in front would put
     the text somewhere else entirely.
     */
    let owner: pid_t

    /** Which app the text belongs to, so its own settings can be looked up. */
    let bundleID: String?

    /** Full contents of the field. */
    let text: String

    /**
     The part to correct, as UTF-16 offsets into `text`.

     A selection made by the user, or the whole field when nothing is selected.
     */
    let range: CFRange

    /** Whether the user made the selection, as opposed to us widening to the whole field. */
    let isUserSelection: Bool

    /**
     Where the caret sat when nothing was selected.

     Worth recording because minimal corrections mostly happen elsewhere in the
     field, so the caret can be put back within a character or two of where the
     user left it instead of being flung to the end of their message.
     */
    let caret: Int?

    /**
     Where to draw the overlay, in top-left origin screen coordinates.

     One rect per visual line of the text being corrected where the app can say,
     so the animation traces the words themselves. A single rect covering the
     whole field where it cannot. Empty when even that is unavailable.
     */
    let rects: [CGRect]

    /** Whether the text is still where it was when the correction started. */
    var isStillFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == owner
    }

    var selectedText: String {
        guard let swiftRange = Range(NSRange(location: range.location, length: range.length), in: text) else {
            return text
        }
        return String(text[swiftRange])
    }
}

enum TextTargetError: Error, Equatable {
    case notTrusted
    case noFocusedElement
    case secureField
    case notEditable
    case unreadable
    case empty
    case tooLong(count: Int)
    case appDenied(bundleID: String)
    /** The user moved to another app while the correction was being worked out. */
    case focusMoved

    /** What to tell the user. Anything they cannot act on stays quiet instead. */
    var userMessage: String? {
        switch self {
        case .notTrusted:
            return "Spellbee needs accessibility access."
        case .secureField:
            return nil
        case .tooLong(let count):
            return "That field is too long to correct (\(count) characters)."
        case .appDenied:
            return nil
        case .focusMoved:
            return "Spellbee stopped because you switched apps."
        case .noFocusedElement, .notEditable, .unreadable, .empty:
            return nil
        }
    }
}

enum TextTargetResolver {
    /**
     Longest field we will take on in one pass.

     Chosen to stay well inside the on-device model's context once the text is
     split into chunks, and to keep an accidental trigger in a long document
     from rewriting everything the user has written.
     */
    static let characterLimit = 8_000

    /**
     Apps where correcting text is more likely to cause harm than help: shells,
     editors and password managers, where the "text field" is usually code, a
     command, or a secret. Seeds the deny-list the user can then edit.
     */
    static let defaultDeniedBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "com.apple.dt.Xcode",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.jetbrains.intellij",
        "com.1password.1password",
        "com.agilebits.onepassword7",
    ]

    static func resolve(denying denied: Set<String> = defaultDeniedBundleIDs) throws -> TextTarget {
        guard AXIsProcessTrusted() else { throw TextTargetError.notTrusted }

        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            throw TextTargetError.noFocusedElement
        }

        if let bundleID = frontmost.bundleIdentifier, denied.contains(bundleID) {
            throw TextTargetError.appDenied(bundleID: bundleID)
        }

        let systemWide = AXUIElementCreateSystemWide()
        guard let focused = systemWide.element(kAXFocusedUIElementAttribute) else {
            throw TextTargetError.noFocusedElement
        }

        /**
         Password fields are marked by subrole rather than role. The constant is
         a C macro that does not reach Swift, so the value is spelled out.
         */
        if focused.string(kAXSubroleAttribute) == "AXSecureTextField" {
            throw TextTargetError.secureField
        }

        guard let text = focused.string(kAXValueAttribute) else {
            throw TextTargetError.unreadable
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextTargetError.empty
        }

        guard text.utf16.count <= characterLimit else {
            throw TextTargetError.tooLong(count: text.utf16.count)
        }

        /**
         Writing back happens by selecting a range and replacing the selection,
         so a field that will not let us move the selection is not writable no
         matter what its value attribute says.
         */
        guard focused.isSettable(kAXSelectedTextRangeAttribute) || focused.isSettable(kAXValueAttribute) else {
            throw TextTargetError.notEditable
        }

        let selection = focused.range(kAXSelectedTextRangeAttribute)
        let hasUserSelection = (selection?.length ?? 0) > 0
        let range = hasUserSelection
            ? selection!
            : CFRange(location: 0, length: text.utf16.count)

        /**
         Enough to identify a field that misbehaves, without ever recording what
         it contains.
         */
        Log.app.info(
            """
            Target in \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown", privacy: .public): \
            role=\(focused.string(kAXRoleAttribute) ?? "none", privacy: .public) \
            subrole=\(focused.string(kAXSubroleAttribute) ?? "none", privacy: .public) \
            chars=\(text.utf16.count, privacy: .public) \
            selectedTextSettable=\(focused.isSettable(kAXSelectedTextAttribute), privacy: .public) \
            valueSettable=\(focused.isSettable(kAXValueAttribute), privacy: .public)
            """
        )

        return TextTarget(
            element: focused,
            owner: frontmost.processIdentifier,
            bundleID: frontmost.bundleIdentifier,
            text: text,
            range: range,
            isUserSelection: hasUserSelection,
            caret: hasUserSelection ? nil : selection?.location,
            rects: rects(of: focused, range: range, in: text)
        )
    }

    /**
     Most lines worth asking about individually.

     Each line costs a round trip to the other app, and past a certain length the
     user cannot see the whole field anyway, so a long passage settles for one
     rect rather than paying for dozens.
     */
    private static let lineQueryLimit = 40

    /**
     Slack when judging whether traced text sits inside its field, since glyph
     rects run a little past the line box for descenders and antialiasing.
     */
    private static let visibilityTolerance: CGFloat = 2

    /**
     Where to put the overlay.

     Tracing the text itself is the nice answer: the animation reads as "these
     words are being worked on" rather than "this box is busy". It is only used
     when every traced rect is verifiably inside the visible field. Text that is
     scrolled out of view reports rects outside the field, or clamped to its
     edge, and either way an animation drawn there is pointing at nothing. When
     that cannot be ruled out, the whole field is the honest answer.
     */
    private static func rects(of element: AXUIElement, range: CFRange, in text: String) -> [CGRect] {
        let field = fieldFrame(of: element)

        if let traced = tracedRects(of: element, range: range, in: text, within: field) {
            Log.app.info("Overlay tracing \(traced.count, privacy: .public) rects")
            return traced
        }

        guard let field else {
            Log.app.info("Overlay has no usable bounds")
            return []
        }

        Log.app.info("Overlay falling back to the whole field")
        return [field]
    }

    private static func fieldFrame(of element: AXUIElement) -> CGRect? {
        guard
            let origin = element.point(kAXPositionAttribute),
            let size = element.size(kAXSizeAttribute),
            size.width > 0, size.height > 0
        else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    /**
     Rects hugging the text, or nil when they cannot be trusted.

     Returns nil rather than a partial answer whenever the field's own frame is
     unknown, because without it there is no way to tell a correctly traced line
     from one describing text that has scrolled away.
     */
    private static func tracedRects(
        of element: AXUIElement,
        range: CFRange,
        in text: String,
        within field: CGRect?
    ) -> [CGRect]? {
        guard let field else { return nil }

        var candidates = perLineRects(of: element, range: range, in: text)

        if candidates.isEmpty,
           let rect = element.boundsForRange(range),
           rect.width > 0, rect.height > 0 {
            candidates = [rect]
        }

        guard !candidates.isEmpty else { return nil }

        let visible = field.insetBy(dx: -visibilityTolerance, dy: -visibilityTolerance)
        guard candidates.allSatisfy(visible.contains) else {
            Log.app.info("Traced text runs outside the visible field")
            return nil
        }

        return candidates
    }

    private static func perLineRects(
        of element: AXUIElement,
        range: CFRange,
        in text: String
    ) -> [CGRect] {
        let rangeEnd = range.location + range.length
        guard
            range.length > 0,
            let firstLine = element.line(forIndex: range.location),
            let lastLine = element.line(forIndex: rangeEnd - 1),
            lastLine >= firstLine,
            lastLine - firstLine < lineQueryLimit
        else {
            return []
        }

        let characters = Array(text.utf16)
        var rects: [CGRect] = []

        for line in firstLine...lastLine {
            guard let lineRange = element.range(forLine: line) else { continue }

            /** Clip to what is actually being corrected. */
            let start = max(lineRange.location, range.location)
            var end = min(lineRange.location + lineRange.length, rangeEnd)

            /**
             A line's range includes its line break, and a rect drawn over that
             stretches to the far edge of the field.
             */
            while end > start, end - 1 < characters.count, isLineBreak(characters[end - 1]) {
                end -= 1
            }

            guard end > start else { continue }

            if let rect = element.boundsForRange(CFRange(location: start, length: end - start)),
               rect.width > 0, rect.height > 0 {
                rects.append(rect)
            }
        }

        return rects
    }

    private static func isLineBreak(_ unit: UInt16) -> Bool {
        unit == 0x000A || unit == 0x000D || unit == 0x2028 || unit == 0x2029
    }
}
