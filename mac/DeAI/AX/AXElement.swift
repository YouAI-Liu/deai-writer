import ApplicationServices
import CoreFoundation
import Foundation
import OSLog

/// Thin typed wrapper over `AXUIElement`. Every AXError is logged.
final class AXElement: @unchecked Sendable {
    let raw: AXUIElement

    private static let log = Logger(subsystem: "com.local.deai", category: "ax")

    init(_ raw: AXUIElement) {
        self.raw = raw
    }

    static func application(pid: pid_t) -> AXElement {
        AXElement(AXUIElementCreateApplication(pid))
    }

    /// Read an attribute; returns nil on any error (logged).
    func attribute<T>(_ name: String) -> T? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(raw, name as CFString, &value)
        guard err == .success else {
            if err != .attributeUnsupported && err != .noValue {
                Self.log.debug("attribute \(name) failed: \(err.rawValue)")
            }
            return nil
        }
        return value as? T
    }

    func attributeNames() -> [String] {
        var names: CFArray?
        let err = AXUIElementCopyAttributeNames(raw, &names)
        guard err == .success else {
            Self.log.debug("attributeNames failed: \(err.rawValue)")
            return []
        }
        return (names as? [String]) ?? []
    }

    /// Parameterized attribute (e.g. AXBoundsForRange, AXLineForIndex).
    func parameterized<T>(_ name: String, _ param: CFTypeRef) -> T? {
        var value: AnyObject?
        let err = AXUIElementCopyParameterizedAttributeValue(raw, name as CFString, param, &value)
        guard err == .success else {
            if err != .attributeUnsupported && err != .noValue {
                Self.log.debug("param \(name) failed: \(err.rawValue)")
            }
            return nil
        }
        return value as? T
    }

    @discardableResult
    func set<T>(_ name: String, _ value: T) -> AXError {
        let err = AXUIElementSetAttributeValue(raw, name as CFString, value as CFTypeRef)
        if err != .success {
            Self.log.debug("set \(name) failed: \(err.rawValue)")
        }
        return err
    }

    // MARK: - common attributes

    var role: String? { attribute(kAXRoleAttribute) }
    var subrole: String? { attribute(kAXSubroleAttribute) }
    var title: String? { attribute(kAXTitleAttribute) }
    var descriptionText: String? { attribute(kAXDescriptionAttribute) }
    var isFocused: Bool { (attribute(kAXFocusedAttribute) as Bool?) ?? false }

    var pid: pid_t? {
        var pid: pid_t = 0
        let err = AXUIElementGetPid(raw, &pid)
        if err != .success {
            Self.log.debug("GetPid failed: \(err.rawValue)")
            return nil
        }
        return pid
    }

    /// AXValue as String (NSString for NSAttributedString values).
    var stringValue: String? {
        if let s: String = attribute(kAXValueAttribute) { return s }
        if let a: NSAttributedString = attribute(kAXValueAttribute) { return a.string }
        return nil
    }

    /// `AXNumberOfCharacters` — cheap length check without pulling the text.
    var numberOfCharacters: Int? {
        attribute(kAXNumberOfCharactersAttribute)
    }

    var position: CGPoint? {
        var p = CGPoint.zero
        guard let v: AXValue = attribute(kAXPositionAttribute),
              AXValueGetValue(v, .cgPoint, &p) else { return nil }
        return p
    }

    var size: CGSize? {
        var s = CGSize.zero
        guard let v: AXValue = attribute(kAXSizeAttribute),
              AXValueGetValue(v, .cgSize, &s) else { return nil }
        return s
    }

    var frame: CGRect? {
        guard let p = position, let s = size else { return nil }
        return CGRect(origin: p, size: s)
    }

    var children: [AXElement] {
        (attribute(kAXChildrenAttribute) as [AXUIElement]?).map { $0.map(AXElement.init) } ?? []
    }

    var parent: AXElement? {
        (attribute(kAXParentAttribute) as AXUIElement?).map(AXElement.init)
    }

    /// The on-screen text viewport: nearest AXScrollArea ancestor frame ∩
    /// `windowFrame`, all in AX top-left screen coordinates. Word pages keep
    /// reporting bounds for off-viewport text (BUG-08), so glyph rects must
    /// be clipped to this, not just the element frame.
    func viewportFrame(windowFrame: CGRect?) -> CGRect? {
        var scroll: CGRect?
        var cur: AXElement? = self
        for _ in 0..<12 {
            guard let c = cur else { break }
            if c.role == "AXScrollArea" {
                scroll = c.frame
                break
            }
            cur = c.parent
        }
        switch (scroll, windowFrame) {
        case let (s?, w?):
            let i = s.intersection(w)
            // no overlap → the element is not visible: empty clip rect
            return i.isNull ? .zero : i
        case let (s?, nil): return s
        case let (nil, w?): return w
        case (nil, nil): return nil
        }
    }

    /// `AXSharedCharacterRange`: when the element's text is a slice of a
    /// larger shared text (e.g. one page of a Word document), this is the
    /// element's location/length in the shared document text. All range-based
    /// parameterized attributes on such an element use the shared offsets.
    var sharedCharacterRange: CFRange? {
        var r = CFRange()
        guard let v: AXValue = attribute("AXSharedCharacterRange"),
              AXValueGetValue(v, .cfRange, &r) else { return nil }
        return r
    }

    /// Length of the element's OWN text (page-local for sliced elements):
    /// the shared range length when present — `AXNumberOfCharacters` reports
    /// the whole document on Word pages, so it is only a last resort.
    var ownTextLength: Int? {
        if let s = sharedCharacterRange { return s.length }
        if let t = stringValue { return t.utf16.count }
        return numberOfCharacters
    }

    var visibleCharacterRange: CFRange? {
        var r = CFRange()
        guard let v: AXValue = attribute(kAXVisibleCharacterRangeAttribute),
              AXValueGetValue(v, .cfRange, &r) else { return nil }
        return r
    }

    var selectedTextRange: CFRange? {
        var r = CFRange()
        guard let v: AXValue = attribute(kAXSelectedTextRangeAttribute),
              AXValueGetValue(v, .cfRange, &r) else { return nil }
        return r
    }

    @discardableResult
    func setSelectedTextRange(_ range: CFRange) -> Bool {
        var r = range
        guard let v = AXValueCreate(.cfRange, &r) else { return false }
        return set(kAXSelectedTextRangeAttribute, v) == .success
    }

    @discardableResult
    func setSelectedText(_ text: String) -> Bool {
        set(kAXSelectedTextAttribute, text) == .success
    }

    /// `AXBoundsForRange` (parameterized) for a UTF-16 CFRange.
    func boundsForRange(_ range: CFRange) -> CGRect? {
        var r = range
        guard let rangeValue = AXValueCreate(.cfRange, &r) else { return nil }
        var rect = CGRect.zero
        guard let v: AXValue = parameterized(kAXBoundsForRangeParameterizedAttribute, rangeValue),
              AXValueGetValue(v, .cgRect, &rect) else { return nil }
        return rect
    }

    /// `AXLineForIndex` (parameterized; takes a CFNumber).
    func lineForIndex(_ index: Int) -> Int? {
        parameterized(kAXLineForIndexParameterizedAttribute, NSNumber(value: index))
    }

    /// `AXRangeForLine` (parameterized; takes a CFNumber).
    func rangeForLine(_ line: Int) -> CFRange? {
        var r = CFRange()
        guard let v: AXValue = parameterized(
            kAXRangeForLineParameterizedAttribute,
            NSNumber(value: line)
        ),
            AXValueGetValue(v, .cfRange, &r) else { return nil }
        return r
    }

    /// `AXStringForRange` (parameterized).
    func stringForRange(_ range: CFRange) -> String? {
        var r = range
        guard let param = AXValueCreate(.cfRange, &r) else { return nil }
        return parameterized(kAXStringForRangeParameterizedAttribute, param)
    }
}
