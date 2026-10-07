import Foundation
import OSLog

/// Apply the user-facing filters to raw core findings. Pure & testable.
///
/// - categories toggled off in settings are removed
/// - markdown findings are removed when the app's per-app rule disables them
/// - `disabledRuleIds` (persistent) are removed
/// - `sessionIgnored` `(ruleId, matchedText)` pairs are removed
enum FindingFilter {
    static func apply(
        _ findings: [Finding],
        text: String,
        settings: AppSettings,
        bundleId: String
    ) -> [Finding] {
        let utf16 = Array(text.utf16)
        return findings.filter { f in
            switch f.category {
            case .grammar: guard settings.grammar else { return false }
            case .aiToneEn: guard settings.aiToneEn else { return false }
            case .aiToneZh: guard settings.aiToneZh else { return false }
            case .markdown:
                guard settings.markdown, settings.markdownEnabled(for: bundleId)
                else { return false }
            }
            if settings.disabledRuleIds.contains(f.ruleId) { return false }
            let s = Int(f.start)
            let e = min(Int(f.end), utf16.count)
            let matched = e > s ? String(decoding: utf16[s..<e], as: UTF16.self) : ""
            if settings.sessionIgnored.contains(
                AppSettings.IgnoreKey(ruleId: f.ruleId, text: matched)
            ) {
                return false
            }
            return true
        }
    }
}

/// Runs checks on a serial background queue. Each `tag` (one per text target)
/// gets its own generation counter and debounce, so typing in one target does
/// not drop another target's pending check — while stale results for the same
/// tag are always dropped.
///
/// Non-grammar rules run on the full text (they are cross-paragraph aware and
/// cheap — ~8 ms per 20k UTF-16 units); grammar runs per paragraph through the
/// LRU cache so typing only re-lints the edited paragraph.
final class CheckService {
    private let log = Logger(subsystem: "com.local.deai", category: "check")

    struct Result {
        let tag: UInt64
        let text: String
        let findings: [Finding]
        let readMs: Double
        let checkMs: Double
        var nonGrammarMs: Double = 0
        var grammarMs: Double = 0
        var filterMs: Double = 0
        var grammarHits: Int = 0
        var grammarMisses: Int = 0
    }

    private let queue = DispatchQueue(label: "com.local.deai.check", qos: .userInitiated)
    /// Heavy objects shared across all tags (harper linter is built once).
    private let checker: Checker
    private let grammarRunner: ParagraphGrammarRunner
    /// Generations/debounce may be written on the caller's thread (main) and
    /// read on `queue` — guard both with a lock.
    private let lock = NSLock()
    private var generations: [UInt64: UInt64] = [:]
    private var debounceItems: [UInt64: DispatchWorkItem] = [:]

    /// Everything that can change the output for a tag — if identical to the
    /// last run, the cached result is delivered without re-running rules.
    /// Only touched on `queue`.
    private struct Inputs: Equatable {
        let text: String
        let bundleId: String
        let options: CheckOptions
        let disabledRuleIds: Set<String>
        let sessionIgnored: Set<AppSettings.IgnoreKey>
    }

    private var lastInputs: [UInt64: Inputs] = [:]
    private var lastResults: [UInt64: Result] = [:]

    init(checker: Checker? = nil, grammarRunner: ParagraphGrammarRunner? = nil) {
        let shared = checker ?? Checker()
        self.checker = shared
        self.grammarRunner = grammarRunner
            ?? ParagraphGrammarRunner(checker: CoreGrammarChecker(checker: shared))
    }

    /// Called on the main queue with fresh results.
    var onResult: ((Result) -> Void)?

    private func nextGeneration(_ tag: UInt64) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let gen = (generations[tag] ?? 0) &+ 1
        generations[tag] = gen
        return gen
    }

    /// `readText` is invoked on the background queue — it must grab the text
    /// (AX read) and return nil if unavailable.
    func schedule(
        tag: UInt64,
        readText: @escaping () -> String?,
        settings: AppSettings,
        bundleId: String
    ) {
        let gen = nextGeneration(tag)
        lock.lock()
        debounceItems[tag]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.run(gen: gen, tag: tag, readText: readText,
                      settings: settings, bundleId: bundleId)
        }
        debounceItems[tag] = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    /// Skip the debounce (e.g. after applying a replacement).
    func scheduleNow(
        tag: UInt64,
        readText: @escaping () -> String?,
        settings: AppSettings,
        bundleId: String
    ) {
        let gen = nextGeneration(tag)
        lock.lock()
        debounceItems[tag]?.cancel()
        debounceItems[tag] = nil
        lock.unlock()
        queue.async { [weak self] in
            self?.run(gen: gen, tag: tag, readText: readText,
                      settings: settings, bundleId: bundleId)
        }
    }

    func invalidate(tag: UInt64) {
        lock.lock()
        generations[tag] = (generations[tag] ?? 0) &+ 1
        debounceItems[tag]?.cancel()
        debounceItems[tag] = nil
        lock.unlock()
        queue.async { [weak self] in
            self?.lastInputs[tag] = nil
            self?.lastResults[tag] = nil
        }
    }

    private func fresh(_ tag: UInt64, _ gen: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generations[tag] == gen
    }

    private func run(
        gen: UInt64,
        tag: UInt64,
        readText: @escaping () -> String?,
        settings: AppSettings,
        bundleId: String
    ) {
        // AX reads + FFI bridging on a worker thread accumulate autoreleased
        // objects; drain them per check rather than at the pool's whim.
        autoreleasepool {
            let t0 = CFAbsoluteTimeGetCurrent()
            guard let text = readText(), fresh(tag, gen) else { return }
            let readMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000

            let inputs = Inputs(
                text: text,
                bundleId: bundleId,
                options: settings.checkOptions(for: bundleId),
                disabledRuleIds: settings.disabledRuleIds,
                sessionIgnored: settings.sessionIgnored
            )
            // identical inputs (e.g. caret-only moves, redundant events) → reuse
            if inputs == lastInputs[tag], let cached = lastResults[tag] {
                deliver(result: cached, tag: tag, gen: gen)
                return
            }

            let t1 = CFAbsoluteTimeGetCurrent()
            // (a) non-grammar rules on the full text
            var opts = settings.checkOptions(for: bundleId)
            opts.grammar = false
            var findings = checker.check(text: text, opts: opts)
            let nonGrammarMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000
            // (b) grammar per paragraph, cached
            var hits = 0
            var misses = 0
            let tg = CFAbsoluteTimeGetCurrent()
            if settings.grammar {
                let pass = grammarRunner.checkAll(text: text)
                findings += pass.findings
                hits = pass.hits
                misses = pass.misses
            }
            let grammarMs = (CFAbsoluteTimeGetCurrent() - tg) * 1000
            let tf = CFAbsoluteTimeGetCurrent()
            findings = FindingFilter.apply(
                findings, text: text, settings: settings, bundleId: bundleId
            )
            findings.sort { ($0.start, $0.end) < ($1.start, $1.end) }
            let filterMs = (CFAbsoluteTimeGetCurrent() - tf) * 1000
            let checkMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000

            guard fresh(tag, gen) else { return }
            let result = Result(
                tag: tag,
                text: text,
                findings: findings,
                readMs: readMs,
                checkMs: checkMs,
                nonGrammarMs: nonGrammarMs,
                grammarMs: grammarMs,
                filterMs: filterMs,
                grammarHits: hits,
                grammarMisses: misses
            )
            lastInputs[tag] = inputs
            lastResults[tag] = result
            deliver(result: result, tag: tag, gen: gen)
        }
    }

    private func deliver(result: Result, tag: UInt64, gen: UInt64) {
        guard fresh(tag, gen) else { return }
        log.debug("check[\(tag)]: \(result.findings.count) findings, read \(result.readMs, format: .fixed(precision: 1))ms, check \(result.checkMs, format: .fixed(precision: 1))ms")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.fresh(tag, gen) else { return }
            self.onResult?(result)
        }
    }
}
