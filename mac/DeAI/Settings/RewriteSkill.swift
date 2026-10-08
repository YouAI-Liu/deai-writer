import Combine
import Foundation
import OSLog

/// Which text language a skill applies to. `any` is offered in both
/// pickers; persisted as `zh|en|any` in the skill file's frontmatter.
public enum SkillLanguage: String, Codable, CaseIterable {
    case zh
    case en
    case any

    public func displayName(_ lang: UILanguage) -> String {
        let key: L10n.Key = switch self {
        case .zh: .skillLangZh
        case .en: .skillLangEn
        case .any: .skillLangAny
        }
        return L10n.t(key, lang)
    }
}

/// One rewrite skill — the user-selectable "style" half of the system
/// prompt. `id` doubles as the `<id>.md` filename in the skills directory;
/// the built-in skill has no file.
public struct RewriteSkill: Equatable, Identifiable {
    public let id: String
    public var name: String
    public var description: String
    public var language: SkillLanguage
    public var body: String
    public var isBuiltin: Bool

    /// The built-in skill's name is localized at display time.
    public func displayName(_ lang: UILanguage) -> String {
        isBuiltin ? L10n.t(.skillBuiltinName, lang) : name
    }

    /// Rough token estimate for the list row: CJK ~1 token/char, the rest
    /// ~4 chars/token.
    public var estimatedTokens: Int {
        RewriteSkillStore.estimatedTokens(body)
    }

    public var isLong: Bool {
        body.count > RewriteSkillStore.longSkillThreshold
    }
}

public enum SkillError: Error, Equatable {
    /// body chars, allowed max
    case tooLarge(Int, Int)
    case emptyName
    /// The picked file was neither a .md nor a folder containing SKILL.md.
    case notMarkdown
    case unreadable
}

/// Rough token estimate: CJK ideographs count 1 each, everything else /4.
private func roughTokens(_ text: String) -> Int {
    var cjk = 0
    var other = 0
    for s in text.unicodeScalars {
        if RewriteLanguageDetect.isCJK(s) { cjk += 1 } else { other += 1 }
    }
    return cjk + other / 4
}

/// zh vs en for the rewrite target text: zh when any CJK ideograph is
/// present and CJK chars are at least 1/3 of the latin-letter count.
enum RewriteLanguageDetect {
    static func isCJK(_ s: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(s.value)
            || (0x3400...0x4DBF).contains(s.value)
            || (0xF900...0xFAFF).contains(s.value)
    }

    static func language(of text: String) -> UILanguage {
        var cjk = 0
        var latin = 0
        for s in text.unicodeScalars {
            if isCJK(s) { cjk += 1 }
            else if (0x41...0x5A).contains(s.value)
                || (0x61...0x7A).contains(s.value) { latin += 1 }
        }
        return (cjk > 0 && cjk * 3 >= latin) ? .zh : .en
    }
}

/// File-backed rewrite skills.
///
/// Layout: `<appSupport>/skills/<id>.md` — plain Markdown with an optional
/// `---`-delimited frontmatter carrying `name`, `description`, `language`.
/// Unknown keys and missing frontmatter are tolerated. The skills
/// directory is watched for create/delete/rename and reloaded (in-place
/// edits are covered the next time the AI tab appears — `reload()` is
/// called there too).
final class RewriteSkillStore: ObservableObject {
    private let log = Logger(subsystem: "com.local.deai", category: "skills")

    static let builtinId = "builtin.deai-default"
    /// Body cap — imports and saves are rejected beyond it.
    static let maxBodyLength = 60_000
    /// Above this the row shows the "long" badge.
    static let longSkillThreshold = 20_000

    /// Setter left internal so @testable code can seed the list.
    @Published var skills: [RewriteSkill]

    /// The `~/Library/Application Support/DeAI/skills` directory.
    let directory: URL
    /// Legacy `style.md` next to `lexicon.json` — migrated on init.
    let legacyStyleFile: URL
    /// Set when init migrated a custom style.md into a skill, so the
    /// caller can point the per-language selections at it.
    private(set) var migratedSkillId: String?

    private var watcher: DispatchSourceFileSystemObject?
    private var watcherFD: Int32 = -1
    private var pendingReload: DispatchWorkItem?

    static var builtin: RewriteSkill {
        RewriteSkill(
            id: builtinId,
            name: L10n.t(.skillBuiltinName, .zh),
            description: "",
            language: .any,
            body: RewritePrompt.defaultStyle,
            isBuiltin: true
        )
    }

    /// `baseDirectory` is the app-support dir (the same one the lexicon
    /// store uses); skills live in its `skills/` subdirectory.
    convenience init(baseDirectory: URL = PersonalLexiconStore.defaultDirectory) {
        self.init(
            directory: baseDirectory.appendingPathComponent(
                "skills", isDirectory: true
            ),
            legacyStyleFile: baseDirectory.appendingPathComponent("style.md")
        )
    }

    init(directory: URL, legacyStyleFile: URL) {
        self.directory = directory
        self.legacyStyleFile = legacyStyleFile
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        skills = []  // uniqueId (inside migrate) reads this
        migrateLegacyStyle()
        skills = [Self.builtin] + Self.loadUserSkills(from: directory)
        startWatching()
    }

    deinit { watcher?.cancel() }

    // MARK: - lookup

    /// Skills eligible for a picker: that language plus `.any`.
    func eligible(for language: SkillLanguage) -> [RewriteSkill] {
        skills.filter { $0.language == language || $0.language == .any }
    }

    /// Resolve a persisted selection to a live skill — deleted ids and
    /// language-ineligible skills fall back to the built-in.
    func resolved(id: String, for language: UILanguage) -> RewriteSkill {
        let lang: SkillLanguage = language == .zh ? .zh : .en
        if let s = skills.first(where: {
            $0.id == id
                && ($0.language == lang || $0.language == .any)
        }) {
            return s
        }
        return Self.builtin
    }

    var fileToReveal: URL { directory }

    static func estimatedTokens(_ body: String) -> Int {
        roughTokens(body)
    }

    // MARK: - frontmatter

    /// Lenient parse: optional `---` frontmatter with `key: value` lines
    /// (name / description / language recognized, others ignored), then
    /// the body verbatim. Handles LF and CRLF.
    static func parse(
        _ data: Data, fallbackName: String
    ) -> (name: String, description: String,
          language: SkillLanguage, body: String) {
        let text = String(data: data, encoding: .utf8) ?? ""
        var name = fallbackName
        var description = ""
        var language: SkillLanguage = .any
        var body = text
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.hasPrefix("---\n") || normalized == "---" {
            var lines = normalized.components(separatedBy: "\n")
            // drop the opening `---`
            lines.removeFirst()
            var frontmatter: [String] = []
            var closed = false
            while !lines.isEmpty {
                let line = lines.removeFirst()
                if line.trimmingCharacters(in: .whitespaces) == "---" {
                    closed = true
                    break
                }
                frontmatter.append(line)
            }
            if closed {
                for line in frontmatter {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    let key = line[..<colon]
                        .trimmingCharacters(in: .whitespaces)
                        .lowercased()
                    let value = line[line.index(after: colon)...]
                        .trimmingCharacters(in: .whitespaces)
                    switch key {
                    case "name":
                        if !value.isEmpty { name = value }
                    case "description":
                        description = value
                    case "language":
                        if let l = SkillLanguage(rawValue: value) {
                            language = l
                        }
                    default:
                        break
                    }
                }
                // body = everything after the closing `---`
                body = lines.joined(separator: "\n")
                if body.hasPrefix("\n") { body.removeFirst() }
            }
        }
        return (name, description, language, body)
    }

    private static func loadUserSkills(from dir: URL) -> [RewriteSkill] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        var out: [RewriteSkill] = []
        for url in files where url.pathExtension == "md" {
            guard let data = try? Data(contentsOf: url) else { continue }
            let stem = url.deletingPathExtension().lastPathComponent
            let parsed = parse(data, fallbackName: stem)
            out.append(
                RewriteSkill(
                    id: stem,
                    name: parsed.name,
                    description: parsed.description,
                    language: parsed.language,
                    body: parsed.body,
                    isBuiltin: false
                )
            )
        }
        return out.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private static func serialize(_ skill: RewriteSkill) -> Data {
        var text = "---\n"
        text += "name: \(skill.name)\n"
        text += "description: \(skill.description)\n"
        text += "language: \(skill.language.rawValue)\n"
        text += "---\n"
        text += skill.body
        return Data(text.utf8)
    }

    // MARK: - edits

    /// A filename-safe unique id: slug of `base` + `-2`, `-3`… when taken.
    func uniqueId(for base: String) -> String {
        let slug = base.lowercased().unicodeScalars.map { s -> Character in
            let v = s.value
            let keep = (0x30...0x39).contains(v)  // 0-9
                || (0x61...0x7A).contains(v)    // a-z
            return keep ? Character(s) : "-"
        }
        var s = String(slug)
        while s.contains("--") { s = s.replacingOccurrences(of: "--", with: "-") }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if s.isEmpty { s = "skill" }
        if !idTaken(s) { return s }
        var n = 2
        while idTaken("\(s)-\(n)") { n += 1 }
        return "\(s)-\(n)"
    }

    private func idTaken(_ id: String) -> Bool {
        id == Self.builtinId
            || skills.contains { $0.id == id }
            || FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("\(id).md").path
            )
    }

    /// Persist a user skill to `<id>.md` (atomic). Validates the cap.
    @discardableResult
    func save(_ skill: RewriteSkill) -> Result<RewriteSkill, SkillError> {
        guard !skill.name
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .failure(.emptyName) }
        guard skill.body.count <= Self.maxBodyLength else {
            return .failure(.tooLarge(skill.body.count, Self.maxBodyLength))
        }
        var s = skill
        s.isBuiltin = false
        do {
            try Self.serialize(s).write(
                to: directory.appendingPathComponent("\(s.id).md"),
                options: .atomic
            )
        } catch {
            log.error("save \(s.id) failed: \(error.localizedDescription)")
            return .failure(.unreadable)
        }
        if let i = skills.firstIndex(where: { $0.id == s.id }) {
            skills[i] = s
        } else {
            skills.append(s)
            skills.sort { a, b in
                a.isBuiltin != b.isBuiltin
                    ? a.isBuiltin
                    : a.name.localizedCompare(b.name) == .orderedAscending
            }
        }
        return .success(s)
    }

    /// Import a `.md` file (or a folder containing `SKILL.md`) into the
    /// skills directory with a fresh unique id.
    @discardableResult
    func importSkill(from url: URL) -> Result<RewriteSkill, SkillError> {
        var file = url
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: url.path, isDirectory: &isDir
        ), isDir.boolValue {
            file = url.appendingPathComponent("SKILL.md")
        }
        guard file.pathExtension.lowercased() == "md" else {
            return .failure(.notMarkdown)
        }
        guard let data = try? Data(contentsOf: file) else {
            return .failure(.unreadable)
        }
        let stem = file.deletingPathExtension().lastPathComponent
        let parsed = Self.parse(data, fallbackName: stem)
        guard parsed.body.count <= Self.maxBodyLength else {
            return .failure(
                .tooLarge(parsed.body.count, Self.maxBodyLength)
            )
        }
        let id = uniqueId(for: parsed.name.isEmpty ? stem : parsed.name)
        let skill = RewriteSkill(
            id: id,
            name: parsed.name,
            description: parsed.description,
            language: parsed.language,
            body: parsed.body,
            isBuiltin: false
        )
        return save(skill)
    }

    /// A built-in "复制为新技能": copies the body into a fresh user skill.
    @discardableResult
    func duplicate(_ skill: RewriteSkill, language: UILanguage = .zh) -> RewriteSkill {
        let id = uniqueId(for: skill.name.isEmpty ? "skill" : skill.name)
        let baseName = L10n.f(.skillCopyName, language, skill.displayName(language))
        let takenNames = Set(skills.map { $0.displayName(language) })
        var name = baseName
        var number = 2
        while takenNames.contains(name) {
            name = "\(baseName) \(number)"
            number += 1
        }
        let copy = RewriteSkill(
            id: id,
            name: name,
            description: skill.description,
            language: skill.language,
            body: skill.body,
            isBuiltin: false
        )
        _ = save(copy)
        return copy
    }

    func delete(id: String) {
        guard let skill = skills.first(where: { $0.id == id }),
              !skill.isBuiltin else { return }
        skills.removeAll { $0.id == id }
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent("\(id).md")
        )
    }

    // MARK: - style.md migration

    /// Custom `style.md` → a `migrated-style` skill + the file renamed to
    /// `style.md.migrated`. A style equal to the default (or absent) is
    /// simply renamed, never imported.
    private func migrateLegacyStyle() {
        guard let data = try? Data(contentsOf: legacyStyleFile),
              let text = String(data: data, encoding: .utf8) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDefault = trimmed.isEmpty
            || trimmed == RewritePrompt.defaultStyle
                .trimmingCharacters(in: .whitespacesAndNewlines)
        let renamed = legacyStyleFile.deletingPathExtension()
            .appendingPathExtension("md.migrated")
        if !isDefault {
            let id = uniqueId(for: "migrated-style")
            let skill = RewriteSkill(
                id: id,
                name: L10n.t(.migratedSkillName, .zh),
                description: "",
                language: .any,
                body: text,
                isBuiltin: false
            )
            do {
                try Self.serialize(skill).write(
                    to: directory.appendingPathComponent("\(id).md"),
                    options: .atomic
                )
                migratedSkillId = id
            } catch {
                log.error("style.md migration write failed: \(error.localizedDescription)")
                return  // keep style.md in place — nothing lost
            }
        }
        try? FileManager.default.moveItem(
            at: legacyStyleFile, to: renamed
        )
    }

    // MARK: - directory watch

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
            guard let self else { return }
            self.pendingReload?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.reload() }
            self.pendingReload = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    /// Rescan the skills directory. Called by the watcher and when the AI
    /// tab appears (in-place edits don't fire the directory source).
    func reload() {
        skills = [Self.builtin] + Self.loadUserSkills(from: directory)
    }
}
