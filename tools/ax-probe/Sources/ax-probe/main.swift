import AppKit
import ApplicationServices
import Foundation

func axErr(_ err: AXError) -> String {
    "\(err) (rawValue=\(err.rawValue))"
}

func copyAttr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    if err != .success {
        print("  \(name): AXError \(axErr(err))")
        return nil
    }
    return value
}

func cfRange(from value: CFTypeRef?) -> CFRange? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var range = CFRange()
    guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
    return range
}

func bounds(for range: CFRange, in element: AXUIElement) -> CGRect? {
    var r = range
    guard let param = AXValueCreate(.cfRange, &r) else {
        print("  AXBoundsForRange \(range.location)+\(range.length): could not create CFRange AXValue")
        return nil
    }
    var out: CFTypeRef?
    let err = AXUIElementCopyParameterizedAttributeValue(
        element, kAXBoundsForRangeParameterizedAttribute as CFString, param, &out)
    guard err == .success, let out, CFGetTypeID(out) == AXValueGetTypeID() else {
        print("  AXBoundsForRange \(range.location)+\(range.length): AXError \(axErr(err))")
        return nil
    }
    var rect = CGRect.zero
    guard AXValueGetValue(out as! AXValue, .cgRect, &rect) else {
        print("  AXBoundsForRange \(range.location)+\(range.length): value is not a CGRect")
        return nil
    }
    print("  AXBoundsForRange \(range.location)+\(range.length): \(rect)")
    return rect
}

// MARK: - 1. Accessibility trust

let promptOptions =
    [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
let trusted = AXIsProcessTrustedWithOptions(promptOptions)
print("AXIsProcessTrustedWithOptions(prompt=true): \(trusted)")
guard trusted else {
    print(
        """
        Not trusted for accessibility. Grant permission to the terminal app running this
        (System Settings → Privacy & Security → Accessibility → enable your terminal),
        then re-run.
        """)
    exit(1)
}

// MARK: - 2. Delay so the user can click into the target app

let delay: TimeInterval =
    CommandLine.arguments.count > 1 ? (Double(CommandLine.arguments[1]) ?? 5) : 5
print("Sleeping \(delay)s — click into the target app (e.g. Microsoft Word)…")
Thread.sleep(forTimeInterval: delay)

// MARK: - 3. Frontmost app

if let app = NSWorkspace.shared.frontmostApplication {
    print(
        "Frontmost app: \(app.localizedName ?? "?") bundle=\(app.bundleIdentifier ?? "?") pid=\(app.processIdentifier)"
    )
} else {
    print("Frontmost app: none")
}

// MARK: - 4. Focused element

// The system-wide element returns kAXErrorCannotComplete for non-bundled CLI processes,
// so query the target application's element directly.
let targetBundle = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil
guard
    let targetApp = targetBundle.flatMap({
        NSRunningApplication.runningApplications(withBundleIdentifier: $0).first
    }) ?? NSWorkspace.shared.frontmostApplication
else {
    print("No target app")
    exit(1)
}
print("Target app: \(targetApp.localizedName ?? "?") pid=\(targetApp.processIdentifier)")
let appElement = AXUIElementCreateApplication(targetApp.processIdentifier)
var focusedValue: CFTypeRef?
let focusErr = AXUIElementCopyAttributeValue(
    appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue)
guard focusErr == .success, let focusedValue,
    CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
else {
    print("AXFocusedUIElement: AXError \(axErr(focusErr))")
    exit(1)
}

func role(_ e: AXUIElement) -> String {
    var v: CFTypeRef?
    AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &v)
    return (v as? String) ?? "?"
}

/// Breadth-first search for the first text-bearing descendant.
func findTextElement(_ root: AXUIElement) -> AXUIElement? {
    var queue = [root]
    var visited = 0
    while !queue.isEmpty, visited < 2000 {
        let e = queue.removeFirst()
        visited += 1
        if ["AXTextArea", "AXTextField", "AXWebArea"].contains(role(e)) { return e }
        var kids: CFTypeRef?
        if AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &kids) == .success,
            let arr = kids as? [AXUIElement]
        {
            queue.append(contentsOf: arr)
        }
    }
    return nil
}

let focusedElement = focusedValue as! AXUIElement
print("Focused element role: \(role(focusedElement))")
let element: AXUIElement
if ["AXTextArea", "AXTextField"].contains(role(focusedElement)) {
    element = focusedElement
} else if let found = findTextElement(focusedElement) {
    print("Focused element is not text; using descendant with role \(role(found))")
    element = found
} else {
    print("No text descendant found under focused element")
    exit(1)
}

print("AXRole: \(copyAttr(element, kAXRoleAttribute) ?? "?" as CFString)")
print("AXSubrole: \(copyAttr(element, kAXSubroleAttribute) ?? "?" as CFString)")
print(
    "AXNumberOfCharacters: \(copyAttr(element, "AXNumberOfCharacters") ?? "?" as CFString)")

if let v = copyAttr(element, kAXValueAttribute) {
    let str: String
    if let s = v as? String {
        str = s
    } else if let a = v as? NSAttributedString {
        str = a.string
    } else {
        str = "<\(CFGetTypeID(v))>"
    }
    print("AXValue: length=\((str as NSString).length) UTF-16 units")
    print("AXValue first 80 chars: \(String(str.prefix(80)))")
}

var selectedRange = CFRange(location: 0, length: 0)
if let r = cfRange(from: copyAttr(element, "AXSelectedTextRange")) {
    selectedRange = r
    print("AXSelectedTextRange: loc=\(r.location) len=\(r.length)")
}

var visibleRange = CFRange(location: 0, length: 0)
if let r = cfRange(from: copyAttr(element, "AXVisibleCharacterRange")) {
    visibleRange = r
    print("AXVisibleCharacterRange: loc=\(r.location) len=\(r.length)")
}

// MARK: - 5. Parameterized attributes

var names: CFArray?
let namesErr = AXUIElementCopyParameterizedAttributeNames(element, &names)
if namesErr == .success, let names = names as? [String] {
    print("Parameterized attributes: \(names)")
} else {
    print("Parameterized attributes: AXError \(axErr(namesErr))")
}

// MARK: - 6. Bounds/range round-trip probes

print("Bounds probes:")
var firstRect: CGRect? = nil
let probes = [
    CFRange(location: 0, length: 1),
    CFRange(location: 0, length: 10),
    CFRange(location: selectedRange.location, length: 1),
    CFRange(location: visibleRange.location + visibleRange.length / 2, length: 1),
]
for probe in probes {
    let rect = bounds(for: probe, in: element)
    if firstRect == nil { firstRect = rect }
}

if let rect = firstRect {
    var point = CGPoint(x: rect.midX, y: rect.midY)
    guard let param = AXValueCreate(.cgPoint, &point) else {
        print("AXRangeForPosition: could not create CGPoint AXValue")
        exit(1)
    }
    var out: CFTypeRef?
    let err = AXUIElementCopyParameterizedAttributeValue(
        element, kAXRangeForPositionParameterizedAttribute as CFString, param, &out)
    if err == .success, let r = cfRange(from: out) {
        print("AXRangeForPosition (\(point)): loc=\(r.location) len=\(r.length)")
    } else {
        print("AXRangeForPosition (\(point)): AXError \(axErr(err))")
    }
} else {
    print("AXRangeForPosition: skipped (no bounds probe succeeded)")
}
