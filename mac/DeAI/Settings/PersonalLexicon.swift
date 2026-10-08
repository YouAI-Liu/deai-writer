import Combine
import Foundation
import OSLog

/// One user-authored lexicon entry. `id`/`note` are persisted metadata —
/// only kind/term/replacement/match cross the FFI boundary.
public struct LexiconEntry: Codable, Equatable, Hashable, Identifiable {
    public enum Kind: String, Codable, CaseIterable {
        case replace
        case avoid
        case keep

        public func displayName(_ lang: UILanguage) -> String {
            let key: L10n.Key = switch self {
            case .replace: .lexiconKindReplace
            case .avoid: .lexiconKindAvoid
            case .keep: .lexiconKindKeep
            }
            return L10n.t(key, lang)
        }
    }

    public enum Match: String, Codable, CaseIterable {
        case exact
        case caseInsensitive
        case wholeWord

        public func displayName(_ lang: UILanguage) -> String {
            let key: L10n.Key = switch self {
            case .exact: .matchExact
            case .caseInsensitive: .matchCaseInsensitive
            case .wholeWord: .matchWholeWord
            }
            return L10n.t(key, lang)
        }
    }

    public var id: UUID
    public var kind: Kind
    public var term: String
    /// `replace` only.
    public var replacement: String?
    public var match: Match
    public var note: String?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        term: String,
        replacement: String? = nil,
        match: Match = .exact,
        note: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.term = term
        self.replacement = replacement
        self.match = match
        self.note = note
    }

    /// An entry that should actually check: non-empty term (within the
    /// length cap) and — for 替换 — a non-empty replacement. Draft rows in
    /// the editor may be invalid; checking and rewrite prompts skip them.
    var isValid: Bool {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, term.count <= PersonalLexiconStore.maxTermLength
        else { return false }
        if kind == .replace, (replacement ?? "").isEmpty { return false }
        return true
    }

    /// The matching-only record the Rust core consumes; nil while the entry
    /// is an incomplete draft.
    var ffi: PersonalEntry? {
        guard isValid else { return nil }
        return PersonalEntry(
            kind: kind == .replace
                ? .replace : kind == .avoid ? .avoid : .keep,
            term: term,
            replacement: replacement,
            matchKind: match == .caseInsensitive
                ? .caseInsensitive
                : match == .wholeWord ? .wholeWord : .exact
        )
    }
}

public enum LexiconError: Error, Equatable {
    case emptyTerm
    case termTooLong
    case limitReached
    case duplicate
}

/// File-backed personal lexicon — `lexicon.json` → `[LexiconEntry]`
/// (max 200, term ≤ 100 chars). The file is watched for external edits
/// and written atomically. A corrupt `lexicon.json` is renamed to
/// `*.corrupt-<timestamp>` before a fresh file is ever written in its place —
/// the bad data is never silently overwritten.
final class PersonalLexiconStore: ObservableObject {
    private let log = Logger(subsystem: "com.local.deai", category: "lexicon")

    @Published private(set) var entries: [LexiconEntry] = []

    static let maxEntries = 200
    static let maxTermLength = 100

    let directory: URL
    private let lexiconURL: URL
    private var watcher: DispatchSourceFileSystemObject?
    private var watcherFD: Int32 = -1
    /// Per-file sources — the directory watcher alone misses in-place
    /// (non-atomic) writes, which don't touch directory entries.
    private var fileWatchers: [URL: DispatchSourceFileSystemObject] = [:]
    /// Coalesces bursts of file-system events during a save.
    private var pendingReload: DispatchWorkItem?

    static var defaultDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeAI", isDirectory: true)
    }

    init(directory: URL = PersonalLexiconStore.defaultDirectory) {
        self.directory = directory
        lexiconURL = directory.appendingPathComponent("lexicon.json")
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        entries = Self.loadEntries(from: lexiconURL, log: log)
        startWatching()
    }

    deinit {
        watcher?.cancel()
        fileWatchers.values.forEach { $0.cancel() }
    }

    // MARK: - persistence

    /// Load entries from disk; a corrupt JSON is preserved under a
    /// `*.corrupt-<ts>` name rather than overwritten on the next save.
    private static func loadEntries(
        from url: URL, log: Logger
    ) -> [LexiconEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        if let decoded = try? JSONDecoder().decode([LexiconEntry].self, from: data) {
            return decoded
        }
        renameCorrupt(url, log: log)
        return []
    }

    private static func renameCorrupt(_ url: URL, log: Logger) {
        let stamp = ISO8601DateFormatter.basic.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp).\(url.pathExtension)")
        do {
            try FileManager.default.moveItem(at: url, to: backup)
            log.error("corrupt file renamed to \(backup.lastPathComponent)")
        } catch {
            log.error("corrupt file could not be renamed: \(error.localizedDescription)")
        }
    }

    private func writeAtomically(_ data: Data, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("write \(url.lastPathComponent) failed: \(error.localizedDescription)")
        }
    }

    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        writeAtomically(data, to: lexiconURL)
    }

    // MARK: - external edits

    /// Watch the containing directory (covers create/replace/delete of both
    /// files); reload after a short coalescing delay, skipping no-ops.
    private func startWatching() {
        watcherFD = open(directory.path, O_EVTONLY)
        guard watcherFD >= 0 else { return }
        let fd = watcherFD
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
        armFileWatcher(for: lexiconURL)
    }

    private func scheduleReload() {
        pendingReload?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reload() }
        pendingReload = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    /// Watch one file directly so in-place writes (no directory change)
    /// trigger a reload. On .rename/.delete the watched vnode is gone: drop
    /// the source and let `reload` re-arm if the path exists again.
    private func armFileWatcher(for url: URL) {
        guard fileWatchers[url] == nil else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let events = source.data
            if events.contains(.rename) || events.contains(.delete) {
                self.fileWatchers[url] = nil
                source.cancel()
            }
            self.scheduleReload()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatchers[url] = source
    }

    /// Re-arm file watchers whose sources were dropped (.rename/.delete) or
    /// never armed (file created after launch / after a corrupt rename).
    private func rearmFileWatchers() {
        if fileWatchers[lexiconURL] == nil {
            armFileWatcher(for: lexiconURL)
        }
    }

    private func reload() {
        let loaded = Self.loadEntries(from: lexiconURL, log: log)
        if loaded != entries {
            entries = loaded
        }
        rearmFileWatchers()
    }

    // MARK: - edits

    @discardableResult
    func addEntry(
        kind: LexiconEntry.Kind,
        term: String,
        replacement: String? = nil,
        match: LexiconEntry.Match = .exact,
        note: String? = nil
    ) -> Result<LexiconEntry, LexiconError> {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyTerm) }
        guard trimmed.count <= Self.maxTermLength else { return .failure(.termTooLong) }
        guard entries.count < Self.maxEntries else { return .failure(.limitReached) }
        let isDup = entries.contains {
            $0.kind == kind && $0.term == trimmed
        }
        guard !isDup else { return .failure(.duplicate) }
        let entry = LexiconEntry(
            kind: kind, term: trimmed,
            replacement: kind == .replace ? replacement : nil,
            match: match, note: note
        )
        entries.append(entry)
        saveEntries()
        return .success(entry)
    }

    /// Settings 添加词条 button: append an editable blank row — the inline
    /// validation flags it until the user types a term. (Strict `addEntry`
    /// stays for the card/rewrite paths, which always carry real terms.)
    @discardableResult
    func addDraft() -> LexiconEntry? {
        guard entries.count < Self.maxEntries else { return nil }
        let entry = LexiconEntry(kind: .replace, term: "")
        entries.append(entry)
        saveEntries()
        return entry
    }

    func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        saveEntries()
    }

    func updateEntry(_ entry: LexiconEntry) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i] = entry
        saveEntries()
    }

    /// Row-level validation for the settings UI (a row is flagged when its
    /// term is empty or duplicates another entry's term+kind).
    func isDuplicate(_ entry: LexiconEntry) -> Bool {
        entries.contains {
            $0.id != entry.id && $0.kind == entry.kind && $0.term == entry.term
        }
    }

    /// Per-entry validation message, or nil.
    func validationError(
        for entry: LexiconEntry, lang: UILanguage = .zh
    ) -> String? {
        if entry.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.t(.errEmptyTerm, lang)
        }
        if entry.term.count > Self.maxTermLength {
            return L10n.f(.errTermTooLong, lang, Self.maxTermLength)
        }
        if isDuplicate(entry) { return L10n.t(.errDuplicate, lang) }
        return nil
    }

    /// "在 Finder 中显示" — reveal `lexicon.json` if it exists, else the dir.
    var fileToReveal: URL {
        FileManager.default.fileExists(atPath: lexiconURL.path)
            ? lexiconURL : directory
    }
}

private extension ISO8601DateFormatter {
    static let basic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        return f
    }()
}
