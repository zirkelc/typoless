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
