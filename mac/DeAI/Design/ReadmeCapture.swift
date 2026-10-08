#if DEBUG
import AppKit
import SwiftUI

/// `DeAI Debug --readme-capture <dir>`: README screenshots at 2x.
///
/// Unlike `--ui-capture` (test fixtures on a bare stage), this composes a
/// fake document page — a real NSTextView with corpus text, the app's own
/// UnderlineView for the underlined phrase, and the real SuggestionCardView
/// floating below it — plus the rewrite panel, settings tabs and the menu,
/// each clipped to a rounded surface with a hairline border and soft
/// shadow on a transparent canvas (legible on GitHub light and dark).
///
/// Findings come from the real check pipeline (`CheckService.checkNow`,
/// same rule passes + filters as production) run on docs/demo/corpus.md
/// passages, never hand-written Finding values. All stores are temp-dir /
/// in-memory fixtures — nothing touches ~/Library/Application Support/DeAI
/// or the Debug app's own defaults.
@MainActor
final class ReadmeCapture {
    private static var active: ReadmeCapture?

    private let root: URL
    private let window: NSWindow
    private let checkService = CheckService()
    /// MenuContent needs a controller even for a static render — a bare
    /// AppController() is inert until `start()`, same as DebugUICapture.
    private let controller = AppController()

    // MARK: corpus

    /// docs/demo/corpus.md passage 2 (备忘录周报): banned-opener 说白了
    /// plus 关键是 / 这意味着 / 华东区 material. Trimmed at runtime to the
    /// featured finding's sentence so the card docks below the text.
    private static let zhSource =
        "说白了，团队完成了对投放流程的优化，检查了素材、落地页、转化路径。"
        + "增长不是简单地增加预算，而是把预算投向已经验证的渠道。"
        + "关键是：先修复支付失败——减少已经进入结算页的客户流失。"
        + "看起来投放效率已经改善，华东区转化率环比提升了 18%。"
        + "关于渠道预算，我们将保留转化稳定的两组广告。"

    /// Passage 5 (英文学术段落): "We used an navigation system" gives a
    /// clean single-suggestion grammar finding; MRI is covered by a keep
    /// entry, matching the corpus's own demo note.
    private static let enSource =
        "This study delves into the role of MRI in planning brain tumor "
        + "surgery. We used an navigation system to compare the images. "
        + "Our findings show that navigation reduced the mean registration "
        + "error from 4 mm to 2 mm."

    private init(directory: String) {
        root = URL(fileURLWithPath: directory, isDirectory: true)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "DeAI Debug — README capture"
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        // Layer-composited content (material blurs, shadows) rasterizes at
        // the window's backing scale — park the window on the Retina
        // screen if there is one so it renders at 2x.
        if let retina = NSScreen.screens.max(by: {
            $0.backingScaleFactor < $1.backingScaleFactor
        }), retina.backingScaleFactor > 1 {
            window.setFrameOrigin(retina.visibleFrame.origin)
        }
        FileHandle.standardError.write(Data(
            "CAP screen scales: \(NSScreen.screens.map(\.backingScaleFactor))\n"
                .utf8))
    }

    static func start(directory: String) {
        MenuContent.hideDebugItems = true
        let capture = ReadmeCapture(directory: directory)
        active = capture
        Task { await capture.run() }
    }

    // MARK: - fixtures (temp dirs + fresh defaults suite; nothing real)

    private struct Fixture {
        let settings: AppSettings
        let secrets: InMemorySecretStore
    }

    private func makeSettings(lang: UILanguage) -> Fixture {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "deai-readme-\(UUID().uuidString)", isDirectory: true)
        let lexicon = PersonalLexiconStore(directory: tmp)
        let skills = RewriteSkillStore(
            directory: tmp.appendingPathComponent("skills", isDirectory: true),
            legacyStyleFile: tmp.appendingPathComponent("style.md")
        )
        let secrets = InMemorySecretStore()
        let settings = AppSettings(
            userDefaults: UserDefaults(
                suiteName: "deai.readme.\(UUID().uuidString)")!,
            secrets: secrets,
            lexicon: lexicon,
            skills: skills
        )
        settings.uiLanguage = lang

        // Personal-lexicon entries (also exercised by the check runs).
        if lang == .zh {
            _ = lexicon.addEntry(kind: .replace, term: "赋能", replacement: "帮助")
            _ = lexicon.addEntry(kind: .avoid, term: "说白了")
            _ = lexicon.addEntry(kind: .keep, term: "华东区")
            _ = lexicon.addEntry(kind: .replace, term: "抓手", replacement: "方法")
            _ = lexicon.addEntry(kind: .avoid, term: "综上所述")
            _ = lexicon.addEntry(kind: .keep, term: "KPI")
        } else {
            _ = lexicon.addEntry(
                kind: .replace, term: "leverage", replacement: "use",
                match: .wholeWord)
            _ = lexicon.addEntry(
                kind: .avoid, term: "delve", match: .wholeWord)
            _ = lexicon.addEntry(kind: .keep, term: "Q3")
            _ = lexicon.addEntry(
                kind: .replace, term: "utilize", replacement: "use",
                match: .wholeWord)
            _ = lexicon.addEntry(kind: .keep, term: "macOS")
            // Corpus passage 5's own note says to keep MRI.
            _ = lexicon.addEntry(kind: .keep, term: "MRI")
        }

        // A configured provider for the AI tab: DeepSeek preset, model set,
        // key stored in the in-memory secret store so it shows 已设置.
        var provider = ProviderConfig(preset: .deepseek)
        provider.model = "deepseek-chat"
        settings.providers = [provider]
        settings.activeProviderId = provider.id
        secrets.set("sk-deai-readme-demo", for: provider.id.uuidString)

        // Rewrite skills: built-in plus two realistic imported ones —
        // modest bodies so no "long skill" warning badge appears.
        if lang == .zh {
            _ = skills.save(RewriteSkill(
                id: "wechat-talk", name: "公众号口语风",
                description: "像跟朋友聊天一样的口语化表达",
                language: .zh,
                body: """
                    把书面语改成自然的口语表达，就像在微信里跟朋友说话：
                    - 多用短句，一句话说一件事
                    - 删掉「值得注意的是」「综上所述」这类套话
                    - 可以保留语气词，但不要夸张的网络用语
                    - 专业术语保留，其余尽量说人话
                    """,
                isBuiltin: false))
            _ = skills.save(RewriteSkill(
                id: "academic-zh", name: "学术论文",
                description: "正式、严谨的学术文体",
                language: .any,
                body: """
                    改写成正式严谨的学术风格：
                    - 使用规范的书面语和学科术语
                    - 删除口语化表达和语气词
                    - 句式完整，逻辑连接词明确
                    - 保持客观，不用第一人称感叹
                    """,
                isBuiltin: false))
        } else {
            _ = skills.save(RewriteSkill(
                id: "plain-business", name: "Plain business English",
                description: "Direct, friendly business writing",
                language: .en,
                body: """
                    Rewrite in plain business English:
                    - Prefer short sentences; one idea per sentence
                    - Cut filler openers like "I hope this email finds you well"
                    - Keep contractions and a warm, direct tone
                    - No jargon — "use" not "utilize", "help" not "leverage"
                    """,
                isBuiltin: false))
            _ = skills.save(RewriteSkill(
                id: "academic-tone", name: "Academic tone",
                description: "Formal register for papers and reports",
                language: .any,
                body: """
                    Rewrite in a formal academic register:
                    - Precise terminology, complete sentences
                    - Remove contractions and conversational asides
                    - Make logical connectors explicit
                    - Keep an objective, impersonal voice
                    """,
                isBuiltin: false))
        }
        return Fixture(settings: settings, secrets: secrets)
    }

    // MARK: - checking (real pipeline)

    private func findings(
        for text: String, settings: AppSettings
    ) async -> [Finding] {
        await withCheckedContinuation { cont in
            checkService.checkNow(
                text: text, settings: settings,
                bundleId: "com.apple.TextEdit"
            ) { findings in
                cont.resume(returning: findings)
            }
        }
    }

    private func matched(_ text: String, _ f: Finding) -> String {
        let u = Array(text.utf16)
        let s = Int(f.start), e = min(Int(f.end), u.count)
        return e > s ? String(decoding: u[s..<e], as: UTF16.self) : ""
    }

    /// Prefer an AI-tone finding with a concrete suggestion (the apply
    /// button is then meaningful); a personal-lexicon replace is a good
    /// showcase too; fall back to grammar, then the first finding.
    /// `suggestions` must not be empty (the card body would render
    /// nothing), a bare-empty suggestion renders the deletion row (still
    /// readable), and punctuation-only suggestions like "," don't count.
    private func featured(_ findings: [Finding]) -> Finding? {
        func score(_ f: Finding, _ i: Int) -> Int {
            var s = 0
            if f.suggestions.isEmpty {
                s -= 50
            } else {
                let concrete = f.suggestions.contains { sugg in
                    sugg.unicodeScalars.contains {
                        CharacterSet.alphanumerics.contains($0)
                    }
                }
                s += concrete ? 20 : 12
            }
            switch f.category {
            case .aiToneZh, .aiToneEn: s += 10
            case .personal: s += 8
            case .grammar: s += 4
            case .markdown: break
            }
            return s - i
        }
        return findings.enumerated().max {
            score($0.element, $0.offset) < score($1.element, $1.offset)
        }?.element
    }

    /// Cut `text` right after the sentence terminator following the
    /// featured finding, so its sentence ends the document and the card
    /// below covers nothing.
    private func trimToSentence(_ text: String, after f: Finding)
        -> String
    {
        let u = Array(text.utf16)
        // . 。 ! ！ ? ？
        let terms: Set<UInt16> = [46, 12290, 33, 65281, 63, 65311]
        var i = Int(f.end)
        while i < u.count {
            if terms.contains(u[i]) {
                return String(decoding: u[0...i], as: UTF16.self)
            }
            i += 1
        }
        return text
    }

    // MARK: - rendering

    /// Swap the window content, apply the appearance, wait for layout.
    private func show<V: View>(_ view: V, size: NSSize, dark: Bool) {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(
            rootView: view.environment(\.colorScheme, dark ? .dark : .light)
        )
        window.setContentSize(size)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// For self-sizing content (rewrite panel, menu): let the hosting view
    /// pick its fitting size.
    private func showFitting<V: View>(_ view: V, dark: Bool) {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(
            rootView: view.environment(\.colorScheme, dark ? .dark : .light)
        )
        window.contentView = host
        host.layout()
        window.setContentSize(host.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Content composited through layers (visual-effect materials,
    /// shadows, text hosting) rasterizes at the window's backing scale —
    /// force every layer to redraw at 2x before the bitmap cache.
    private func forceLayerScale(_ view: NSView?) {
        func walk(_ layer: CALayer) {
            // ImageLayer (SF Symbols / SwiftUI Image) and ContentLayer
            // hold pre-rendered image contents — display() blanks them,
            // and even ImageLayer's _SwiftUILayerDelegate doesn't
            // regenerate. Every other layer is a backing store or
            // container that safely re-rasterizes at 2x.
            let name = String(describing: type(of: layer))
            let imageCarrying = name == "ImageLayer"
                || name == "ContentLayer"
                || (layer.contents != nil && layer.delegate == nil)
            if !imageCarrying {
                layer.contentsScale = 2
                layer.contentsGravity = .resize
                layer.setNeedsDisplay()
            }
            layer.sublayers?.forEach(walk)
        }
        if let layer = view?.layer { walk(layer) }
    }

    /// 2x bitmap of the current content view.
    private func snapshot(rescaleLayers: Bool = true) -> NSBitmapImageRep? {
        guard let view = window.contentView else { return nil }
        if rescaleLayers { forceLayerScale(view) }
        let bounds = view.bounds
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * 2),
            pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        return rep
    }

    /// Snapshot the content view at 2x into `<root>/<lang>/<name>.png`.
    private func save(
        _ name: String, lang: UILanguage, after delay: Double = 0.8,
        rescaleLayers: Bool = true
    ) async throws {
        try await Task.sleep(for: .seconds(delay))
        guard let view = window.contentView,
              let rep = snapshot(rescaleLayers: rescaleLayers) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let bounds = view.bounds
        guard let data = rep.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        let dir = root.appendingPathComponent(lang.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        try data.write(
            to: dir.appendingPathComponent(name + ".png"), options: .atomic)
        FileHandle.standardError.write(
            Data("CAP \(lang.rawValue)/\(name) \(Int(bounds.width))x\(Int(bounds.height))@2x\n".utf8))
    }

    /// Renders a settings pane's entire scroll document (not just the
    /// 660pt viewport) at 2x — the shot then shows complete sections
    /// instead of a mid-scroll slice.
    private func scrollDocument() -> (image: NSImage, rep: NSBitmapImageRep)? {
        var scroll: NSScrollView?
        func find(_ v: NSView?) {
            guard let v, scroll == nil else { return }
            if let s = v as? NSScrollView, s.documentView != nil {
                scroll = s
                return
            }
            v.subviews.forEach(find)
        }
        find(window.contentView)
        guard let doc = scroll?.documentView else { return nil }
        doc.layoutSubtreeIfNeeded()
        forceLayerScale(doc)
        doc.displayIfNeeded()
        let b = doc.bounds
        guard b.width > 0, b.height > 0,
              let rep = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: Int(b.width * 2), pixelsHigh: Int(b.height * 2),
                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                  isPlanar: false, colorSpaceName: .deviceRGB,
                  bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = b.size
        doc.cacheDisplay(in: b, to: rep)
        let img = NSImage(size: b.size)
        img.addRepresentation(rep)
        return (img, rep)
    }

    /// Centres (pixels) of the first gap run of each section-boundary
    /// cluster in a rendered settings document: a "gap" is a run of
    /// ≥16px rows that are all pane background; runs <80px apart merge
    /// into one cluster (they straddle a section heading). Cutting at a
    /// cluster's first gap lands the edge right before/after a full
    /// section instead of mid-card or under an orphaned heading.
    private func gapBoundaries(_ rep: NSBitmapImageRep) -> [(Int, Int)] {
        guard let data = rep.bitmapData else { return [] }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        let stride = rep.bytesPerRow, bpp = rep.bitsPerPixel / 8
        func isGap(_ y: Int) -> Bool {
            let mo = y * stride + 8 * bpp
            let margin =
                (Int(data[mo]) + Int(data[mo + 1]) + Int(data[mo + 2])) / 3
            var match = 0, total = 0
            var x = 16
            while x < w - 16 {
                let o = y * stride + x * bpp
                let lum =
                    (Int(data[o]) + Int(data[o + 1]) + Int(data[o + 2])) / 3
                if abs(lum - margin) <= 8 { match += 1 }
                total += 1
                x += 20
            }
            return total > 0 && match * 100 >= total * 96
        }
        var firsts: [(Int, Int)] = []
        var runStart = -1, prevEnd = -1
        for y in 24..<h {
            if isGap(y) {
                if runStart < 0 { runStart = y }
            } else {
                if runStart >= 0, y - runStart >= 16 {
                    if firsts.isEmpty || runStart - prevEnd > 80 {
                        firsts.append((runStart, y))
                    }
                    prevEnd = y
                }
                runStart = -1
            }
        }
        FileHandle.standardError.write(Data(
            "CAP boundaries(px): \(firsts)\n".utf8))
        return firsts
    }

    /// Card with the production editor phase — apply just completes.
    private func makeCard(_ f: Finding, _ matched: String, _ lang: UILanguage)
        -> SuggestionCardModel
    {
        let m = SuggestionCardModel(finding: f, matchedText: matched)
        m.lang = lang
        m.onApply = { _, done in
            DispatchQueue.main.async { done(true) }
        }
        return m
    }

    /// Lays the document out offscreen (same 640pt width as the stage) to
    /// learn where the underlined phrase and the last text line land.
    private func measureDoc(_ text: String, finding: Finding)
        -> (anchor: CGRect, textBottom: CGFloat)
    {
        let v = ReadmeDocView(text: text)
        v.underlined = (
            finding,
            NSRange(
                location: Int(finding.start),
                length: Int(finding.end - finding.start))
        )
        v.frame = NSRect(x: 0, y: 0, width: 640, height: 500)
        v.layoutSubtreeIfNeeded()
        return (v.anchorRect, v.textBottom)
    }

    /// Rendered height of a card — found by scanning a transparent
    /// 2x bitmap of it for the last opaque row.
    private func measureCardHeight(_ model: SuggestionCardModel) -> CGFloat {
        let host = NSHostingView(rootView:
            SuggestionCardView(model: model, autoDismiss: false)
                .environment(\.deaiReducedMotionOverride, true)
                .frame(width: 300))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 700)
        host.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 1400,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0),
              let data = rep.bitmapData else { return 170 }
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        let stride = rep.bytesPerRow
        // alpha>8 also catches the card's soft shadow, oversizing the stage —
        // require a run of solid pixels (the card surface itself).
        for y in (0..<rep.pixelsHigh).reversed() {
            var x = 0
            var solid = 0
            while x < rep.pixelsWide {
                if data[y * stride + x * 4 + 3] > 200 {
                    solid += 1
                }
                x += 6
            }
            if solid > 30 {
                return CGFloat(y) / 2 + 2
            }
        }
        return 170
    }

    /// Render the stage once taller than needed, then find the lowest
    /// painted row inside the page (card surface or its shadow — page and
    /// card share colours, but the shadow always reads darker/lighter
    /// than the uniform page bottom). Returns the stage height that
    /// leaves ~16pt of page below the card.
    private func fitStageHeight(
        text: String, finding: Finding, range: NSRange,
        selection: NSRange?, anchor: CGRect, cardY: CGFloat,
        measuredCardH: CGFloat, model: SuggestionCardModel
    ) async -> CGFloat {
        let rough = cardY + measuredCardH + 80
        show(
            ReadmeFramed {
                ReadmeCardStage(
                    text: text, finding: finding, range: range,
                    selection: selection, anchor: anchor, cardY: cardY,
                    height: rough, dark: false, model: model)
            },
            size: NSSize(width: 640 + 56, height: rough + 56),
            dark: false)
        try? await Task.sleep(for: .seconds(0.8))
        guard let rep = snapshot(), let data = rep.bitmapData
        else { return cardY + measuredCardH + 30 }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        let stride = rep.bytesPerRow
        func px(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
            let i = y * stride + x * 4
            return (Int(data[i]), Int(data[i + 1]),
                    Int(data[i + 2]), Int(data[i + 3]))
        }
        let bg = px(90, h - 66)
        var y = h - 60
        while y > 60 {
            var diff = 0
            var x = 60
            while x < w - 60 {
                let p = px(x, y)
                if p.3 > 200
                    && abs(p.0 - bg.0) + abs(p.1 - bg.1)
                        + abs(p.2 - bg.2) > 8
                {
                    diff += 1
                }
                x += 6
            }
            if diff > 8 {
                let contentBottom = CGFloat(y) / 2 - 28
                return min(rough, contentBottom + 16)
            }
            y -= 1
        }
        return cardY + measuredCardH + 30
    }

    /// Frame a rendered settings document like a live capture: the image
    /// starts at the boundary nearest `topTargetPt` (0 keeps the top)
    /// and ends at the last boundary at/below `bottomMaxPt` (or the full
    /// document), then the shared clip/border/shadow chrome.
    private func saveDocument(
        _ name: String, lang: UILanguage,
        topTargetPt: CGFloat, bottomMaxPt: CGFloat
    ) async throws {
        guard let (img, rep) = scrollDocument() else {
            try await save(name, lang: lang, after: 0.1)
            return
        }
        let bounds = gapBoundaries(rep)
        func pt(_ px: Int) -> CGFloat { CGFloat(px) / 2 }
        var top: CGFloat = 0
        if topTargetPt > 0, let b = bounds.min(by: {
            abs(CGFloat($0.0) - topTargetPt * 2)
                < abs(CGFloat($1.0) - topTargetPt * 2)
        }) {
            // 40px (~20pt) above the header = the gap's tail end, so the
            // cropped image keeps pane background above the first
            // section header like the live view does.
            top = pt(max(b.0, b.1 - 40))
        }
        var bottom = img.size.height
        if bottomMaxPt.isFinite,
           let b = bounds.filter({
               CGFloat(($0.0 + $0.1) / 2) <= bottomMaxPt * 2
           }).last {
            bottom = pt((b.0 + b.1) / 2)
        }
        if bottom <= top + 40 {
            top = 0
            bottom = img.size.height
        }
        showFitting(
            ReadmeFramed {
                ZStack(alignment: .topLeading) {
                    Image(nsImage: img)
                        .offset(y: -top)
                }
                .frame(
                    width: img.size.width, height: bottom - top,
                    alignment: .top)
                .clipped()
            },
            dark: false)
        // The embedded rep is already 2x — redrawing its layers would
        // blank the NSImage contents.
        try await save(name, lang: lang, rescaleLayers: false)
    }

    // MARK: - run

    private func run() async {
        do {
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: true)
            for lang in [UILanguage.en, .zh] {
                let fixture = makeSettings(lang: lang)
                let source = lang == .en ? Self.enSource : Self.zhSource
                // Pick the featured finding on the full source, then trim
                // the text to end with that finding's sentence and check
                // again — the displayed doc is what was checked.
                guard let firstPick = featured(
                    await findings(for: source, settings: fixture.settings))
                else { continue }
                let paragraph = trimToSentence(source, after: firstPick)
                let found = await findings(
                    for: paragraph, settings: fixture.settings)
                let summary = found.map {
                    "\($0.ruleId)[\($0.start)-\($0.end)]sugg=\($0.suggestions)"
                }.joined(separator: " | ")
                FileHandle.standardError.write(
                    Data("CAP \(lang.rawValue) findings: \(summary)\n".utf8))
                guard let featured = featured(found),
                      !found.isEmpty else { continue }
                let range = NSRange(
                    location: Int(featured.start),
                    length: Int(featured.end - featured.start))
                let featuredMatched = matched(paragraph, featured)

                // Measure the document + card, then size the stage to the
                // card's bottom — the text ends with the featured
                // sentence, so nothing is covered.
                let geom = measureDoc(paragraph, finding: featured)
                let cardY = geom.textBottom + 8

                let plain = makeCard(featured, featuredMatched, lang)
                let plainStageH = await fitStageHeight(
                    text: paragraph, finding: featured, range: range,
                    selection: nil, anchor: geom.anchor, cardY: cardY,
                    measuredCardH: measureCardHeight(plain), model: plain)
                show(
                    ReadmeFramed {
                        ReadmeCardStage(
                            text: paragraph, finding: featured,
                            range: range, selection: nil,
                            anchor: geom.anchor, cardY: cardY,
                            height: plainStageH, dark: false,
                            model: plain)
                    },
                    size: NSSize(
                        width: 640 + 56, height: plainStageH + 56),
                    dark: false)
                try await save("card-light", lang: lang)
                show(
                    ReadmeFramed {
                        ReadmeCardStage(
                            text: paragraph, finding: featured,
                            range: range, selection: nil,
                            anchor: geom.anchor, cardY: cardY,
                            height: plainStageH, dark: true,
                            model: plain)
                    },
                    size: NSSize(
                        width: 640 + 56, height: plainStageH + 56),
                    dark: true)
                try await save("card-dark", lang: lang)

                // selection check: whole paragraph selected, the stepper
                // on the featured finding (e.g. 4/8) — same underline as
                // the card shots keeps the two images consistent.
                let stepIndex = found.firstIndex {
                    $0.start == featured.start && $0.end == featured.end
                        && $0.ruleId == featured.ruleId
                } ?? min(1, found.count - 1)
                let stepModel = makeCard(featured, featuredMatched, lang)
                stepModel.setSessionStep(
                    index: stepIndex, count: found.count)
                let stepStageH = await fitStageHeight(
                    text: paragraph, finding: featured, range: range,
                    selection: NSRange(
                        location: 0, length: paragraph.utf16.count),
                    anchor: geom.anchor, cardY: cardY,
                    measuredCardH: measureCardHeight(stepModel),
                    model: stepModel)
                show(
                    ReadmeFramed {
                        ReadmeCardStage(
                            text: paragraph, finding: featured,
                            range: range,
                            selection: NSRange(
                                location: 0, length: paragraph.utf16.count),
                            anchor: geom.anchor, cardY: cardY,
                            height: stepStageH, dark: false,
                            model: stepModel)
                    },
                    size: NSSize(
                        width: 640 + 56, height: stepStageH + 56),
                    dark: false)
                try await save("selection-check", lang: lang)

                // rewrite panel — word-level edits so 记住改法 shows pairs
                let rewrite = RewritePanelModel()
                rewrite.lang = lang
                rewrite.phase = .result
                rewrite.canRetry = true
                if lang == .zh {
                    rewrite.original =
                        "说白了，本周我们通过数据驱动的方式赋能了每一个环节。"
                    rewrite.result = "本周我们通过数据驱动的方式帮助了每一个环节。"
                } else {
                    rewrite.original =
                        "I wanted to delve into the results of our Q3 campaign, "
                        + "which played a pivotal role in our growth."
                    rewrite.result =
                        "I wanted to dig into the results of our Q3 campaign, "
                        + "which played a key role in our growth."
                }
                rewrite.rememberPairs = RewriteDiff.wordPairs(
                    original: rewrite.original, result: rewrite.result)
                rewrite.rememberChecked = Set(rewrite.rememberPairs.indices)
                rewrite.rememberExpanded = !rewrite.rememberPairs.isEmpty
                FileHandle.standardError.write(Data(
                    "CAP \(lang.rawValue) rewrite pairs: \(rewrite.rememberPairs)\n"
                        .utf8))
                showFitting(
                    ReadmeFramed { RewritePanelView(model: rewrite) },
                    dark: false)
                try await save("rewrite-panel", lang: lang)

                // settings: render the scroll view's whole document, then
                // crop at section boundaries — Check keeps Language +
                // Categories + Sensitivity, AI keeps Rewrite Skills +
                // Shortcut (provider card omitted), lexicon in full.
                show(
                    ReadmeFramed {
                        SettingsView(
                            settings: fixture.settings,
                            currentBundleId: "com.apple.TextEdit",
                            initialTab: 0)
                    },
                    size: NSSize(width: 560 + 56, height: 660 + 56),
                    dark: false)
                try await Task.sleep(for: .seconds(0.7))
                try await saveDocument(
                    "settings-check", lang: lang,
                    topTargetPt: 0, bottomMaxPt: 800)

                show(
                    ReadmeFramed {
                        SettingsView(
                            settings: fixture.settings,
                            initialTab: 2)
                    },
                    size: NSSize(width: 560 + 56, height: 660 + 56),
                    dark: false)
                try await Task.sleep(for: .seconds(0.7))
                // raw-only: provider section, to eyeball the API-key row —
                // saveDocument swaps the window to the cropped composite,
                // so every document capture needs the pane re-shown.
                try await saveDocument(
                    "settings-provider", lang: lang,
                    topTargetPt: 0, bottomMaxPt: 530)
                show(
                    ReadmeFramed {
                        SettingsView(
                            settings: fixture.settings,
                            initialTab: 2)
                    },
                    size: NSSize(width: 560 + 56, height: 660 + 56),
                    dark: false)
                try await Task.sleep(for: .seconds(0.7))
                try await saveDocument(
                    "settings-ai", lang: lang,
                    topTargetPt: 530, bottomMaxPt: .infinity)

                show(
                    ReadmeFramed {
                        SettingsView(
                            settings: fixture.settings,
                            initialTab: 3)
                    },
                    size: NSSize(width: 560 + 56, height: 660 + 56),
                    dark: false)
                try await Task.sleep(for: .seconds(0.7))
                try await saveDocument(
                    "settings-lexicon", lang: lang,
                    topTargetPt: 0, bottomMaxPt: .infinity)

                // menu panel, app types expanded, no debug items
                showFitting(
                    ReadmeFramed {
                        MenuContent(
                            controller: controller,
                            groupsExpanded: true,
                            settings: fixture.settings)
                    },
                    dark: false)
                try await save("menu", lang: lang)
            }
            print("README capture complete")
        } catch {
            FileHandle.standardError.write(
                Data("README capture failed: \(error)\n".utf8))
        }
        NSApp.terminate(nil)
    }
}

// MARK: - document stage

/// A fake document page: an NSTextView showing the corpus paragraph with
/// the app's real UnderlineView drawing the finding's phrase underline.
/// Reports the underlined phrase's first glyph rect (page coords,
/// top-left origin) so the card can dock beneath it.
private final class ReadmeDocView: NSView {
    let textView: NSTextView
    let underlineView: UnderlineView
    /// The single finding to underline (nil = none).
    var underlined: (finding: Finding, range: NSRange)?
    var selection: NSRange?
    /// Measured after layout: the underlined phrase's first glyph rect and
    /// the last text line's bottom edge, in page coordinates (top-left
    /// origin). Read via `measureDoc` so the card can be placed before
    /// the stage is ever shown.
    private(set) var anchorRect: CGRect = .zero
    private(set) var textBottom: CGFloat = 0

    /// Text inset inside the page (top-left origin — the view is flipped).
    private let inset = NSSize(width: 32, height: 26)

    override var isFlipped: Bool { true }

    init(text: String) {
        textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .textColor
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.string = text
        // Selected text renders in the system highlight colour even though
        // the text view is never first responder in a capture window.
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor
        ]
        underlineView = UnderlineView(frame: .zero)
        super.init(frame: .zero)
        addSubview(textView)
        addSubview(underlineView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        let textFrame = NSRect(
            x: inset.width, y: inset.height,
            width: w - 2 * inset.width, height: h - 2 * inset.height)
        textView.frame = textFrame
        textView.textContainer?.containerSize = NSSize(
            width: textFrame.width, height: .greatestFiniteMagnitude)
        underlineView.frame = textFrame
        guard let lm = textView.layoutManager,
              let tc = textView.textContainer else { return }
        lm.ensureLayout(for: tc)
        textBottom = textFrame.minY + lm.usedRect(for: tc).height

        if let selection, selection.length > 0 {
            textView.selectedRanges = [NSValue(range: selection)]
        }

        if let u = underlined {
            let glyph = lm.glyphRange(
                forCharacterRange: u.range, actualCharacterRange: nil)
            var rects: [CGRect] = []
            lm.enumerateEnclosingRects(
                forGlyphRange: glyph,
                withinSelectedGlyphRange: NSRange(
                    location: NSNotFound, length: 0),
                in: tc
            ) { rect, _ in
                rects.append(rect)
            }
            // textView is flipped, UnderlineView is not — mirror the rects
            // vertically into underline-view coordinates.
            let uh = underlineView.bounds.height
            let local = rects.map {
                CGRect(x: $0.minX, y: uh - $0.maxY,
                       width: $0.width, height: $0.height)
            }
            underlineView.render([
                PositionedFinding(finding: u.finding, rects: local)
            ])
            if let first = rects.first {
                anchorRect = first.offsetBy(
                    dx: textFrame.minX, dy: textFrame.minY)
            }
        }
    }
}

private struct ReadmeDoc: NSViewRepresentable {
    let text: String
    var underlined: (finding: Finding, range: NSRange)?
    var selection: NSRange?
    var dark = false

    func makeNSView(context: Context) -> ReadmeDocView {
        let v = ReadmeDocView(text: text)
        v.underlined = underlined
        v.selection = selection
        v.underlineView.previewAppearance = NSAppearance(
            named: dark ? .darkAqua : .aqua)
        return v
    }

    func updateNSView(_ v: ReadmeDocView, context: Context) {
        v.underlined = underlined
        v.selection = selection
        v.needsLayout = true
    }
}

/// Document page + the real suggestion card. Geometry is precomputed by
/// `measureDoc`/`measureCardHeight`: the corpus text ends with the
/// featured finding's sentence, the card docks just below the last text
/// line near the phrase's x — nothing is covered.
private struct ReadmeCardStage: View {
    let text: String
    let finding: Finding
    let range: NSRange
    let selection: NSRange?
    let anchor: CGRect
    let cardY: CGFloat
    let height: CGFloat
    let dark: Bool

    @StateObject private var model: SuggestionCardModel

    private static let stageWidth: CGFloat = 640

    init(text: String, finding: Finding, range: NSRange,
         selection: NSRange?, anchor: CGRect, cardY: CGFloat,
         height: CGFloat, dark: Bool, model: SuggestionCardModel) {
        self.text = text
        self.finding = finding
        self.range = range
        self.selection = selection
        self.anchor = anchor
        self.cardY = cardY
        self.height = height
        self.dark = dark
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ReadmeDoc(
                text: text,
                underlined: (finding, range),
                selection: selection,
                dark: dark)
            .frame(width: Self.stageWidth, height: height)
            SuggestionCardView(model: model, autoDismiss: false)
                .environment(\.deaiReducedMotionOverride, true)
                .frame(width: 300)
                .shadow(
                    color: .black.opacity(0.22), radius: 12,
                    x: 0, y: 5)
                .offset(x: cardX, y: cardY)
        }
        .frame(width: Self.stageWidth, height: height)
        .clipped()
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// Card left edge near the phrase's start, clamped inside the page.
    private var cardX: CGFloat {
        min(max(anchor.minX - 14, 10), Self.stageWidth - 300 - 10)
    }
}

/// README chrome: the UI surface clipped to a 14pt continuous-corner
/// rect, a hairline border in the theme's border colour, a soft shadow,
/// then 28pt of transparent canvas around it.
private struct ReadmeFramed<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .clipShape(
                RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(DeAIDesign.border, lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(0.14), radius: 24, x: 0, y: 8)
            .padding(28)
    }
}
#endif
