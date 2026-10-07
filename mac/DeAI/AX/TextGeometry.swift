import AppKit
import CoreGraphics

/// A finding plus its on-screen rects (Cocoa bottom-left coordinates).
struct PositionedFinding {
    let finding: Finding
    let rects: [CGRect]
}

enum TextGeometry {
    /// AX uses a top-left origin at the primary screen; Cocoa uses bottom-left.
    /// `primaryMaxY` = `NSScreen.screens[0].frame.maxY`.
    static func axToCocoa(_ axRect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(
            x: axRect.minX,
            y: primaryMaxY - axRect.maxY,
            width: axRect.width,
            height: axRect.height
        )
    }

    /// Split `[start, end)` into per-line segments using the element's
    /// AXLineForIndex/AXRangeForLine. If line lookup is unsupported, return the
    /// whole range as a single segment.
    static func lineSegments(
        start: Int,
        end: Int,
        lineForIndex: (Int) -> Int?,
        rangeForLine: (Int) -> CFRange?
    ) -> [CFRange] {
        guard end > start,
              let firstLine = lineForIndex(start),
              let lastLine = lineForIndex(end - 1) else {
            return [CFRange(location: start, length: max(0, end - start))]
        }
        var out: [CFRange] = []
        var cursor = start
        var line = firstLine
        while cursor < end, line <= lastLine {
            guard let lineRange = rangeForLine(line), lineRange.length > 0 else {
                break
            }
            let segEnd = min(lineRange.location + lineRange.length, end)
            if segEnd > cursor {
                out.append(CFRange(location: cursor, length: segEnd - cursor))
            }
            cursor = segEnd
            line += 1
        }
        if cursor < end {
            // line lookup gave up mid-range — close out with the remainder
            out.append(CFRange(location: cursor, length: end - cursor))
        }
        return out
    }

    /// Keep only rects that have area and intersect the element's own frame.
    /// Both must be in the same coordinate space (caller: AX top-left space).
    static func filterRects(_ rects: [CGRect], elementFrame: CGRect?) -> [CGRect] {
        rects.filter { r in
            r.width > 0.5 && r.height > 0.5
                && (elementFrame.map { r.intersects($0) } ?? true)
        }
    }

    /// Clip each rect to `clip` (drop fully outside, shrink partial), then to
    /// `elementFrame` if given. All rects must share the same coordinate
    /// space (caller: AX top-left). Word page elements report glyph bounds
    /// for the whole page — including lines scrolled out of the document
    /// viewport — so clipping to the scroll viewport is required (BUG-08).
    static func clipRects(
        _ rects: [CGRect],
        elementFrame: CGRect?,
        clip: CGRect?
    ) -> [CGRect] {
        rects.compactMap { r in
            var c = r
            if let clip {
                c = c.intersection(clip)
            }
            if let e = elementFrame {
                c = c.intersection(e)
            }
            guard !c.isNull, c.width > 0.5, c.height > 0.5 else { return nil }
            return c
        }
    }

    /// Translate an element-local `[start, end)` span into shared-document
    /// offsets and clip it to the element's visible range (shared space).
    /// Returns nil when the span lies fully outside the visible range.
    static func globalSpan(
        start: Int,
        end: Int,
        baseOffset: Int,
        visible: CFRange
    ) -> CFRange? {
        let s = max(start + baseOffset, visible.location)
        let e = min(end + baseOffset, visible.location + visible.length)
        guard s < e else { return nil }
        return CFRange(location: s, length: e - s)
    }

    /// Position one finding's shared-space range `[s, e)` to on-screen rects:
    /// split into line segments (global offsets), fetch AX bounds, clip
    /// degenerate/off-viewport rects **in AX space** (element frame +
    /// optional scroll viewport), then convert to Cocoa. Clipping in AX
    /// space is required — the element frame is AX top-left; comparing
    /// Cocoa rects against it drops everything when the window is near the
    /// top of the primary screen (BUG-02).
    static func positionRects(
        start s: Int,
        end e: Int,
        elementFrameAX: CGRect?,
        viewportAX: CGRect? = nil,
        primaryMaxY: CGFloat,
        boundsForRange: (CFRange) -> CGRect?,
        lineForIndex: (Int) -> Int?,
        rangeForLine: (Int) -> CFRange?
    ) -> [CGRect] {
        let segments = lineSegments(
            start: s,
            end: e,
            lineForIndex: lineForIndex,
            rangeForLine: rangeForLine
        )
        let axRects = clipRects(
            segments.compactMap(boundsForRange),
            elementFrame: elementFrameAX,
            clip: viewportAX
        )
        return axRects.map { axToCocoa($0, primaryMaxY: primaryMaxY) }
    }

    /// Position each finding of `findings` (element-local UTF-16 ranges)
    /// inside the element. `baseOffset` is the element's start in the shared
    /// document text (Word pages): every AX range API on a sliced element
    /// takes shared offsets, so findings are translated by `baseOffset`
    /// before querying. `AXVisibleCharacterRange` is already in shared
    /// space, so clipping happens there directly. At most `maxFindings`.
    static func position(
        findings: [Finding],
        element: AXElement,
        primaryMaxY: CGFloat,
        baseOffset: Int = 0,
        viewportAX: CGRect? = nil,
        maxFindings: Int = 300
    ) -> [PositionedFinding] {
        let localLen = element.ownTextLength ?? 0
        let visible: CFRange = element.visibleCharacterRange
            ?? CFRange(location: baseOffset, length: localLen)
        let elementFrame = element.frame

        var out: [PositionedFinding] = []
        for f in findings.prefix(maxFindings) {
            guard let span = globalSpan(
                start: Int(f.start),
                end: Int(f.end),
                baseOffset: baseOffset,
                visible: visible
            ) else { continue }
            let rects = positionRects(
                start: span.location,
                end: span.location + span.length,
                elementFrameAX: elementFrame,
                viewportAX: viewportAX,
                primaryMaxY: primaryMaxY,
                boundsForRange: { element.boundsForRange($0) },
                lineForIndex: { element.lineForIndex($0) },
                rangeForLine: { element.rangeForLine($0) }
            )
            if !rects.isEmpty {
                out.append(PositionedFinding(finding: f, rects: rects))
            }
        }
        return out
    }
}
