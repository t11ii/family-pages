import AppKit
import Foundation
import Observation

struct PublishedPage: Identifiable {
    let path: String // relative to pages/, e.g. "study/quiz.html"
    let title: String
    let modified: Date
    var id: String { path }
}

enum Phase: Equatable {
    case idle, publishing, deploying, live
    case failed(String)
}

@MainActor @Observable
final class Publisher {
    static let shared = Publisher()
    static let newCategoryTag = "__new__"

    var repoPath: String {
        didSet {
            UserDefaults.standard.set(repoPath, forKey: "repoPath")
            refresh()
        }
    }

    // The file being published and what we learned from it.
    var file: URL? { didSet { loadFileInfo() } }
    var fileTitle = ""
    var warnings: [String] = []
    var category = "misc"
    var newCategory = ""
    var name = ""
    private var fallbackStem = "page"

    // What's already in the repo.
    var categories: [String] = []
    var pages: [PublishedPage] = []
    var baseURL: URL?

    // Progress of the current publish.
    var phase: Phase = .idle
    var log = ""
    var publishedURL: URL?

    private init() {
        repoPath = UserDefaults.standard.string(forKey: "repoPath")
            ?? Bundle.main.object(forInfoDictionaryKey: "FPRepoPath") as? String
            ?? FileManager.default.currentDirectoryPath
        refresh()
    }

    // MARK: - Derived state

    var pagesDir: URL { URL(fileURLWithPath: repoPath).appendingPathComponent("pages").resolvingSymlinksInPath() }
    var isRepoValid: Bool { FileManager.default.isExecutableFile(atPath: repoPath + "/publish.sh") }
    var isBusy: Bool { phase == .publishing || phase == .deploying }

    var effectiveCategory: String {
        category == Self.newCategoryTag ? Self.sanitize(newCategory).lowercased() : category
    }
    var finalName: String { Self.htmlName(name, fallback: fallbackStem) }

    var targetURL: URL? { baseURL.flatMap { URL(string: $0.absoluteString + "\(effectiveCategory)/\(finalName)") } }

    var replacesExisting: Bool {
        !effectiveCategory.isEmpty && FileManager.default.fileExists(
            atPath: pagesDir.appendingPathComponent(effectiveCategory).appendingPathComponent(finalName).path)
    }

    var canPublish: Bool { file != nil && !isBusy && !effectiveCategory.isEmpty && isRepoValid }

    func url(for page: PublishedPage) -> URL? {
        baseURL.flatMap { URL(string: $0.absoluteString + page.path) }
    }

    // MARK: - Actions

    func refresh() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: pagesDir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        categories = dirs
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .filter { !$0.hasPrefix(".") }
            .sorted()
        if category != Self.newCategoryTag && !categories.contains(category) {
            category = categories.first ?? Self.newCategoryTag
        }

        var found: [PublishedPage] = []
        let prefix = pagesDir.path + "/"
        for url in (fm.enumerator(at: pagesDir, includingPropertiesForKeys: [.contentModificationDateKey])?.allObjects ?? [])
            .compactMap({ $0 as? URL })
        where url.pathExtension.lowercased() == "html" {
            let path = url.resolvingSymlinksInPath().path.replacingOccurrences(of: prefix, with: "")
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            found.append(PublishedPage(path: path, title: Self.readTitle(url) ?? url.lastPathComponent, modified: modified))
        }
        pages = found.sorted { $0.modified > $1.modified }
        baseURL = Self.siteURL(repoPath: repoPath)
    }

    func publish() async {
        guard let file, canPublish else { return }
        let cat = effectiveCategory
        let fname = finalName

        phase = .publishing
        log = ""
        publishedURL = nil
        let result = await Shell.run(["./publish.sh", file.path, cat, fname], cwd: repoPath)
        log = result.output
        guard result.status == 0 else {
            phase = .failed("Publishing failed. Open Details below to see why.")
            return
        }

        publishedURL = baseURL.flatMap { URL(string: $0.absoluteString + "\(cat)/\(fname)") }
        if let publishedURL { copy(publishedURL) }
        refresh()
        if category == Self.newCategoryTag {
            category = cat
            newCategory = ""
        }

        if result.output.contains("No changes to publish") {
            phase = .live
            return
        }
        phase = .deploying
        phase = await waitForDeploy()
    }

    func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    // MARK: - Private

    /// Waits for the GitHub Actions run triggered by the last push to finish.
    private func waitForDeploy() async -> Phase {
        let sha = await Shell.run(["git", "rev-parse", "HEAD"], cwd: repoPath).trimmed

        var runID = ""
        for _ in 0..<20 {
            let r = await Shell.run(["gh", "run", "list", "--commit", sha, "--json", "databaseId",
                                     "--jq", ".[0].databaseId // empty"], cwd: repoPath)
            if r.status == 0, Int(r.trimmed) != nil {
                runID = r.trimmed
                break
            }
            try? await Task.sleep(for: .seconds(3))
        }
        guard !runID.isEmpty else {
            return .failed("Uploaded, but couldn't find the deploy on GitHub. Check the repo's Actions tab.")
        }

        for _ in 0..<120 {
            let r = await Shell.run(["gh", "run", "view", runID, "--json", "status,conclusion",
                                     "--jq", ".status + \" \" + .conclusion"], cwd: repoPath)
            let parts = r.trimmed.split(separator: " ")
            if parts.first == "completed" {
                return parts.dropFirst().first == "success"
                    ? .live
                    : .failed("The deploy failed on GitHub. Check the repo's Actions tab.")
            }
            try? await Task.sleep(for: .seconds(5))
        }
        return .failed("The deploy is taking unusually long. Check the repo's Actions tab.")
    }

    private func loadFileInfo() {
        publishedURL = nil
        if !isBusy { phase = .idle }
        log = ""
        guard let file else {
            fileTitle = ""
            warnings = []
            name = ""
            return
        }

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        fallbackStem = "page-" + stamp.string(from: Date())
        name = Self.htmlName(file.lastPathComponent, fallback: fallbackStem)
        fileTitle = Self.readTitle(file) ?? "(no <title>, so the index will show the file name)"

        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        var found: [String] = []
        let ext = file.pathExtension.lowercased()
        if ext != "html" && ext != "htm" {
            found.append("This doesn't look like an HTML file.")
        }
        if text.range(of: "name=\"viewport\"", options: .caseInsensitive) == nil
            && text.range(of: "name='viewport'", options: .caseInsensitive) == nil {
            found.append("No viewport tag, so the page may look tiny on phones.")
        }
        if text.contains("src=\"http://") || text.contains("href=\"http://") {
            found.append("Loads something over http://, which iPhone Safari will block.")
        }
        warnings = found
    }

    // MARK: - Helpers

    /// Same rule as publish.sh: spaces become dashes, only URL-safe characters are kept.
    static func sanitize(_ s: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return String(s.replacingOccurrences(of: " ", with: "-").filter { allowed.contains($0) })
    }

    static func htmlName(_ raw: String, fallback: String) -> String {
        var stem = sanitize(raw)
        for ext in [".html", ".htm"] where stem.lowercased().hasSuffix(ext) {
            stem = String(stem.dropLast(ext.count))
            break
        }
        stem = stem.trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return (stem.isEmpty ? fallback : stem) + ".html"
    }

    static func readTitle(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: 65536)) ?? Data(), as: UTF8.self)
        guard let match = head.firstMatch(of: #/<title[^>]*>(.*?)</title>/#.ignoresCase().dotMatchesNewlines()) else {
            return nil
        }
        let title = match.1.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return title.isEmpty ? nil : title
    }

    /// https://<user>.github.io/<repo>/ from the origin remote in .git/config.
    static func siteURL(repoPath: String) -> URL? {
        guard let config = try? String(contentsOfFile: repoPath + "/.git/config", encoding: .utf8),
              let m = config.firstMatch(of: #/github\.com[:/]([^/\s]+)/([^\s]+?)(?:\.git)?\s/#) else {
            return nil
        }
        let user = String(m.1)
        let repo = String(m.2)
        return repo.lowercased() == "\(user.lowercased()).github.io"
            ? URL(string: "https://\(user).github.io/")
            : URL(string: "https://\(user).github.io/\(repo)/")
    }
}
