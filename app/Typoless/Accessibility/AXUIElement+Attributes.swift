@preconcurrency import ApplicationServices
import Foundation

/**
 Thin typed access to the accessibility APIs.

 Every call here can fail for reasons that are entirely normal (the element does
 not implement the attribute, the app is slow to answer, focus moved), so the
 accessors return optionals rather than throwing. The caller decides what is
 worth reacting to.
 */
extension AXUIElement {
    func string(_ attribute: String) -> String? {
        value(attribute) as? String
    }

    func range(_ attribute: String) -> CFRange? {
        guard let raw = value(attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }

        var result = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &result) else { return nil }
        return result
    }

    func point(_ attribute: String) -> CGPoint? {
        guard let raw = value(attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }

        var result = CGPoint.zero
        guard AXValueGetValue(raw as! AXValue, .cgPoint, &result) else { return nil }
        return result
    }

    func size(_ attribute: String) -> CGSize? {
        guard let raw = value(attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }

        var result = CGSize.zero
        guard AXValueGetValue(raw as! AXValue, .cgSize, &result) else { return nil }
        return result
    }

    func element(_ attribute: String) -> AXUIElement? {
        guard let raw = value(attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    /** Screen rect of a character range, in the top-left origin space AX reports. */
    func boundsForRange(_ range: CFRange) -> CGRect? {
        var mutableRange = range
        guard
            let parameter = AXValueCreate(.cfRange, &mutableRange),
            let raw = parameterizedValue(kAXBoundsForRangeParameterizedAttribute, parameter: parameter),
            CFGetTypeID(raw) == AXValueGetTypeID()
        else {
            return nil
        }

        var result = CGRect.zero
        guard AXValueGetValue(raw as! AXValue, .cgRect, &result) else { return nil }
        return result
    }

    /** Which visual line a character sits on, counting from zero. */
    func line(forIndex index: Int) -> Int? {
        guard
            let raw = parameterizedValue(
                kAXLineForIndexParameterizedAttribute,
                parameter: index as CFNumber
            )
        else {
            return nil
        }
        return (raw as? NSNumber)?.intValue
    }

    /** The character range making up a visual line, including its line break. */
    func range(forLine line: Int) -> CFRange? {
        guard
            let raw = parameterizedValue(
                kAXRangeForLineParameterizedAttribute,
                parameter: line as CFNumber
            ),
            CFGetTypeID(raw) == AXValueGetTypeID()
        else {
            return nil
        }

        var result = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &result) else { return nil }
        return result
    }

    /**
     What this element holds, in the order it is drawn.

     Text elements give their text, images give the emoji they stand for, and
     anything else is reported as itself so the caller can decline to rewrite a
     field it cannot reproduce. A group is a container rather than content, so
     it contributes its children and nothing of its own.

     Bounded like the roles below, and for the same reason: it runs between
     reading a field and writing to it, while the user waits.
     */
    func parts(depth: Int = 3, limit: Int = 64) -> [FieldPart] {
        guard depth >= 0, limit > 0 else { return [] }

        var raw: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(self, kAXChildrenAttribute as CFString, &raw) == .success,
            let children = raw as? [AXUIElement],
            !children.isEmpty
        else {
            return []
        }

        var parts: [FieldPart] = []

        for child in children.prefix(limit) {
            let role = child.string(kAXRoleAttribute) ?? "AXUnknown"

            switch role {
            case "AXStaticText":
                parts.append(.text(child.string(kAXValueAttribute) ?? ""))

            case "AXImage":
                if let name = FieldText.emojiName(fromDescription: child.string(kAXDescriptionAttribute)) {
                    parts.append(.emoji(name))
                } else {
                    parts.append(.unrepresentable(role: role))
                }

            case "AXGroup", "AXList", "AXRow", "AXCell", "AXUnknown":
                let inner = child.parts(depth: depth - 1, limit: limit - parts.count)
                /** A container that reports nothing is content this cannot see. */
                parts += inner.isEmpty ? [.unrepresentable(role: role)] : inner

            default:
                parts.append(.unrepresentable(role: role))
            }

            if parts.count >= limit { break }
        }

        return parts
    }

    /**
     The roles of everything under this element, to a small depth.

     Bounded on purpose. This runs between reading a field and writing to it,
     while the user waits, and a composer in a chat app can hold a thousand
     elements once the conversation above it is counted. Two levels and a few
     dozen elements are enough to find an image sitting beside the text, which
     is what this exists to notice.
     */
    func descendantRoles(depth: Int = 2, limit: Int = 64) -> [String] {
        guard depth >= 0, limit > 0 else { return [] }

        var raw: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(self, kAXChildrenAttribute as CFString, &raw) == .success,
            let children = raw as? [AXUIElement]
        else {
            return []
        }

        var roles: [String] = []

        for child in children.prefix(limit) {
            roles.append(child.string(kAXRoleAttribute) ?? "AXUnknown")
            roles += child.descendantRoles(depth: depth - 1, limit: limit - roles.count)

            if roles.count >= limit { break }
        }

        return roles
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(self, attribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    @discardableResult
    func set(_ attribute: String, to value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(self, attribute as CFString, value)
    }

    @discardableResult
    func setRange(_ attribute: String, to range: CFRange) -> AXError {
        var mutableRange = range
        guard let value = AXValueCreate(.cfRange, &mutableRange) else { return .failure }
        return set(attribute, to: value)
    }

    /**
     Whether the system's keyboard focus is still on this exact element.

     Everything else here addresses an element directly, so aiming at the wrong
     one merely fails. Pasting does not: it is a keystroke, and it lands on
     whatever is focused at that moment, in whatever application. Anything about
     to paste has to ask this first.
     */
    var hasSystemFocus: Bool {
        guard let focused = AXUIElementCreateSystemWide().element(kAXFocusedUIElementAttribute) else {
            return false
        }

        return CFEqual(focused, self)
    }

    private func value(_ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &result) == .success else {
            return nil
        }
        return result
    }

    private func parameterizedValue(_ attribute: String, parameter: CFTypeRef) -> CFTypeRef? {
        var result: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                self,
                attribute as CFString,
                parameter,
                &result
            ) == .success
        else {
            return nil
        }
        return result
    }
}
