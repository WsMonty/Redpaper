import AppKit
import SwiftUI

@main
struct EasyBackgroundsApp: App {
    @StateObject private var model = AppModel()

    init() {
        if CommandLine.arguments.contains("--selftest") {
            Wallhaven.selfTest()
            Schedule.selfTest()
            Release.selfTest()
            print("selftest ok")
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopupView().environmentObject(model)
        } label: {
            Image(nsImage: .menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}

extension NSImage {
    /// Template glyph matching the app icon: a framed mountain with a sun and two little eyes.
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let frame = NSBezierPath(roundedRect: NSRect(x: 1.25, y: 2.25, width: 15.5, height: 13.5), xRadius: 3.5, yRadius: 3.5)
            frame.lineWidth = 1.5
            frame.stroke()
            frame.addClip()
            let back = NSBezierPath()
            back.move(to: NSPoint(x: 8, y: 2))
            back.line(to: NSPoint(x: 11.4, y: 8.4))
            back.curve(to: NSPoint(x: 12.6, y: 8.4), controlPoint1: NSPoint(x: 11.8, y: 9.1), controlPoint2: NSPoint(x: 12.2, y: 9.1))
            back.line(to: NSPoint(x: 18, y: 2))
            back.fill()
            let front = NSBezierPath()
            front.move(to: NSPoint(x: 0, y: 2))
            front.line(to: NSPoint(x: 6.6, y: 11.2))
            front.curve(to: NSPoint(x: 8.4, y: 11.2), controlPoint1: NSPoint(x: 7.2, y: 12), controlPoint2: NSPoint(x: 7.8, y: 12))
            front.line(to: NSPoint(x: 15, y: 2))
            front.fill()
            NSBezierPath(ovalIn: NSRect(x: 11.6, y: 10.4, width: 3, height: 3)).fill()
            NSGraphicsContext.current?.compositingOperation = .clear // cut out the eyes
            NSBezierPath(ovalIn: NSRect(x: 5.75, y: 6.6, width: 1.3, height: 1.6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 7.95, y: 6.6, width: 1.3, height: 1.6)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

enum Frequency: String, CaseIterable, Identifiable {
    case manual, hourly, sixHours, daily, weekly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .manual: "Manually only"
        case .hourly: "Every hour"
        case .sixHours: "Every 6 hours"
        case .daily: "Every day"
        case .weekly: "Every week"
        }
    }
}

enum Schedule {
    /// `minutes`: time of day (0..<1440). `weekday`: 1 = Sunday … 7 = Saturday.
    static func next(after last: Date, _ frequency: Frequency, minutes: Int, weekday: Int,
                     calendar: Calendar = .current) -> Date? {
        var match = DateComponents(hour: minutes / 60, minute: minutes % 60)
        switch frequency {
        case .manual: return nil
        case .hourly: return last.addingTimeInterval(3600)
        case .sixHours: return last.addingTimeInterval(6 * 3600)
        case .daily: break
        case .weekly: match.weekday = weekday
        }
        return calendar.nextDate(after: last, matching: match, matchingPolicy: .nextTime)
    }

    static func selfTest() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let mon9 = cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 9))! // a Monday
        precondition(next(after: mon9, .daily, minutes: 8 * 60, weekday: 1, calendar: cal) == mon9.addingTimeInterval(23 * 3600))
        precondition(next(after: mon9, .daily, minutes: 14 * 60 + 30, weekday: 1, calendar: cal) == mon9.addingTimeInterval(5.5 * 3600))
        precondition(next(after: mon9, .weekly, minutes: 9 * 60, weekday: 2, calendar: cal) == mon9.addingTimeInterval(7 * 86400))
        precondition(next(after: mon9, .hourly, minutes: 0, weekday: 1, calendar: cal) == mon9.addingTimeInterval(3600))
        precondition(next(after: mon9, .manual, minutes: 0, weekday: 1, calendar: cal) == nil)
    }
}

/// The newest GitHub release. Installs are built from source, so we only point people to it.
struct Release: Decodable {
    let tag_name: String
    let html_url: URL
    var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }

    /// Set by build.sh from the latest git tag; nil when run outside the app bundle.
    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

    static func latest() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/WsMonty/easy-backgrounds/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(Release.self, from: data)
    }

    /// "1.10" > "1.9" > "1.2.1" > "1.2"
    static func isNewer(_ version: String, than current: String) -> Bool {
        version.compare(current, options: .numeric) == .orderedDescending
    }

    static func selfTest() {
        precondition(isNewer("1.10", than: "1.9"))
        precondition(isNewer("1.2.1", than: "1.2"))
        precondition(!isNewer("1.0", than: "1.0"))
        precondition(!isNewer("1.0", than: "1.1"))
        precondition(Release(tag_name: "v2.0", html_url: URL(string: "https://x")!).version == "2.0")
        let notes = parseNotes("# Release notes\nintro\n\n## 1.3\n- c\n\n## 1.2\n- a\n- b\n", upTo: "1.2")
        precondition(notes.map(\.version) == ["1.2"] && notes[0].notes == "- a\n- b")
    }

    /// This build's RELEASE_NOTES.md (copied in by build.sh), newest first.
    static let notes: [(version: String, notes: String)] = {
        guard let url = Bundle.main.url(forResource: "RELEASE_NOTES", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parseNotes(text, upTo: current)
    }()

    /// Splits on "## <version>" headings, skipping versions newer than `current` (not released yet).
    static func parseNotes(_ text: String, upTo current: String?) -> [(version: String, notes: String)] {
        ("\n" + text).components(separatedBy: "\n## ").dropFirst().compactMap { section in
            let lines = section.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let version = lines[0].trimmingCharacters(in: .whitespaces)
            if let current, isNewer(version, than: current) { return nil }
            return (version, lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespacesAndNewlines) : "")
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var status = ""
    /// Set while waiting out Wallhaven's rate limit, so the popup can count down.
    @Published private(set) var waitUntil: Date?
    /// What's on each screen, keyed by display id.
    @Published private(set) var applied: [String: Applied] = AppModel.load("applied") ?? [:] {
        didSet { save(applied, "applied") }
    }
    /// The last `historyLimit` wallpapers, newest first. Older ones are deleted from disk.
    @Published private(set) var history: [Applied] = AppModel.load("history") ?? [] {
        didSet { save(history, "history") }
    }
    /// This run's best candidates per screen group (the first one was applied), to switch between
    /// without downloading again.
    @Published private(set) var picks: [Picks] = AppModel.load("picks") ?? [] {
        didSet { save(picks, "picks") }
    }
    /// Wallpapers the user chose to keep, newest first. Never deleted automatically.
    @Published private(set) var kept: [Applied] = AppModel.load("kept") ?? [] {
        didSet { save(kept, "kept") }
    }
    /// True after "Keep this wallpaper": the schedule is off until "Restart schedule".
    @Published private(set) var paused = UserDefaults.standard.bool(forKey: "paused") {
        didSet { UserDefaults.standard.set(paused, forKey: "paused") }
    }
    /// A newer release than this build, if "Check for updates" found one.
    @Published private(set) var availableUpdate: Release?
    /// True after a new version was installed, until its release notes are opened or the popup closes.
    @Published private(set) var justUpdated = false
    @Published var showingReleaseNotes = false
    static let historyLimit = 7
    /// Candidates kept per run (Settings, 1–5).
    static var pickCount: Int { min(max(UserDefaults.standard.integer(forKey: "pickCount"), 1), 5) }
    private var lastUpdateCheck = Date.distantPast
    private var retryAfter: Date?
    private var timer: Timer?
    private var cache: [String: (date: Date, posts: [Post])] = [:]
    /// Wallpaper ids already shown (or skipped), newest last, so "Next" and scheduled updates never repeat.
    private var seen = UserDefaults.standard.stringArray(forKey: "seen") ?? [] {
        // Never trimmed: "never repeat" has to hold forever.
        // ~10 bytes per id: even hourly × 5 for a year is ~0.5 MB.
        didSet { UserDefaults.standard.set(seen, forKey: "seen") }
    }
    /// Index into the selected topics whose turn is next.
    private var rotation = UserDefaults.standard.integer(forKey: "rotation") {
        didSet { UserDefaults.standard.set(rotation, forKey: "rotation") }
    }

    init() {
        UserDefaults.standard.register(defaults: [
            "topics": Wallhaven.defaultTopics.joined(separator: ","), "selectedTopics": Wallhaven.defaultTopics.joined(separator: ","),
            "minFit": SettingsTab.safeFit, "sameOnAllScreens": true, "pickCount": 3,
            "frequency": Frequency.daily.rawValue, "updateMinutes": 9 * 60, "weekday": 2, "checkForUpdates": true,
        ])
        if let version = Release.current, UserDefaults.standard.string(forKey: "notesSeenVersion") != version {
            // No record yet: a fresh install, or an install from before release notes (it has run before).
            justUpdated = UserDefaults.standard.string(forKey: "notesSeenVersion") != nil
                || UserDefaults.standard.double(forKey: "lastUpdate") > 0
            if !justUpdated { dismissUpdateNotice() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 10
        let ws = NSWorkspace.shared.notificationCenter
        // Catch runs missed while asleep.
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // The public API only sets the current Space, so apply again on every Space switch.
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reapply() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reapply()
                guard NSScreen.screens.contains(where: { self.applied[$0.key] == nil }) else { return }
                let same = UserDefaults.standard.bool(forKey: "sameOnAllScreens")
                if self.paused || same, let shown = self.current.first { self.restore(shown) } else { await self.update() }
            }
        }
        reapply()
        tick()
    }

    /// Distinct wallpapers on the connected screens.
    var current: [Applied] {
        var seen = Set<String>()
        return NSScreen.screens.compactMap { applied[$0.key] }.filter { seen.insert($0.file).inserted }
    }

    /// Selected topics, stored comma-separated (AppStorage can't hold arrays).
    static var topics: [String] { (UserDefaults.standard.string(forKey: "selectedTopics") ?? "").commaList }

    static var sort: Sort { Sort(rawValue: UserDefaults.standard.string(forKey: "sort") ?? "") ?? .new }

    var nextUpdate: Date? {
        let d = UserDefaults.standard
        return Schedule.next(
            after: Date(timeIntervalSince1970: d.double(forKey: "lastUpdate")),
            Frequency(rawValue: d.string(forKey: "frequency") ?? "") ?? .daily,
            minutes: d.integer(forKey: "updateMinutes"),
            weekday: d.integer(forKey: "weekday"))
    }

    /// Shows a new wallpaper, taking turns between the selected topics. `fresh` refetches
    /// results (scheduled runs); otherwise cached results are reused, so "Next" usually costs no request.
    func update(fresh: Bool = false) async {
        guard !busy else { return }
        busy = true
        status = ""
        defer { busy = false }

        let d = UserDefaults.standard
        let topics = Self.topics
        guard !topics.isEmpty else { status = "Select at least one topic in Settings."; return }
        let minFit = d.double(forKey: "minFit")
        let maxAge: TimeInterval = fresh ? 60 : 30 * 60
        do {
            var exclude = Set(seen)
            var missed = 0
            var newPicks: [Picks] = []
            // One group with every screen (same image everywhere), or one group per screen.
            let same = d.bool(forKey: "sameOnAllScreens")
            let groups = same ? [NSScreen.screens] : NSScreen.screens.map { [$0] }
            for group in groups {
                let sizes = group.map(\.pixelSize)
                // Only ask Wallhaven for images big enough to reach minFit on the group's smallest screen.
                // This drops odd shapes that would just pass (e.g. 4:3 on 16:10); fine for real wallpapers.
                let small = sizes.min { $0.width * $0.height < $1.width * $1.height } ?? .zero
                let atleast = CGSize(width: (small.width * minFit.squareRoot()).rounded(.down),
                                     height: (small.height * minFit.squareRoot()).rounded(.down))
                var found: [(Post, URL)] = []
                // Try the topic whose turn it is, then the following ones, until there are enough candidates.
                let pickCount = Self.pickCount
                for step in 0..<topics.count where found.count < pickCount {
                    let i = (rotation + step) % topics.count
                    var got: [(Post, URL)] = []
                    // All of page 1 already seen (e.g. the same top list all day): look a few pages further.
                    for page in 1...3 {
                        let results = try await posts(topics[i], page: page, atleast: atleast, maxAge: maxAge)
                        got = await pick(from: results, for: sizes, minFit: minFit, exclude: exclude,
                                         limit: pickCount - found.count)
                        if !got.isEmpty || results.count < 24 { break } // 24 per page: fewer means the last one
                    }
                    if found.isEmpty, !got.isEmpty { rotation = (i + 1) % topics.count }
                    found += got
                    exclude.formUnion(got.map(\.0.id))
                }
                let candidates = found.map { post, file in
                    Applied(id: post.id, file: file.path, title: post.title,
                            permalink: post.permalink, topic: post.topic)
                }
                guard let shown = candidates.first else { missed += 1; continue }
                newPicks.append(Picks(screens: group.map(\.key), items: candidates))
                seen += candidates.map(\.id) // offered, so later runs don't repeat them
                // Same everywhere: also cover screens not connected right now (e.g. an external display
                // that reconnects only after wake), so reapply() gives them this image, not the old one.
                if same { applied = applied.mapValues { _ in shown } }
                for screen in group {
                    try Wallpaper.set(URL(fileURLWithPath: shown.file), on: screen)
                    applied[screen.key] = shown
                }
                // Screens may have connected while we waited for Wallhaven.
                if same { reapply() }
                addToHistory(shown)
            }
            picks = newPicks
            cleanUp()
            d.set(Date().timeIntervalSince1970, forKey: "lastUpdate")
            retryAfter = nil
            if missed > 0 {
                status = "No new image with ≥ \(Int((minFit * 100).rounded())) % fit in \(Self.sort == .new ? "the newest" : "the top") wallpapers"
                    + (groups.count > 1 ? " for \(missed) screen(s)." : ".")
            }
        } catch {
            status = error.localizedDescription
            // Offline (e.g. just woke up): try again next minute. Wallhaven trouble: back off.
            retryAfter = Date().addingTimeInterval(error is URLError ? 60 : 15 * 60)
        }
    }

    /// Puts a history or kept wallpaper back on every screen (until the next scheduled update).
    func restore(_ item: Applied) {
        guard FileManager.default.fileExists(atPath: item.file) else {
            history.removeAll { $0.id == item.id }
            kept.removeAll { $0.id == item.id }
            status = "That image is no longer on disk."
            return
        }
        applied = applied.mapValues { _ in item } // disconnected screens too, see update()
        for screen in NSScreen.screens {
            try? Wallpaper.set(URL(fileURLWithPath: item.file), on: screen)
            applied[screen.key] = item
        }
        status = ""
    }

    /// Switches to another of this run's candidates on its screens. The schedule is unaffected.
    func choose(_ item: Applied, in group: Picks) {
        if UserDefaults.standard.bool(forKey: "sameOnAllScreens") {
            restore(item)
        } else {
            for screen in NSScreen.screens where group.screens.contains(screen.key) {
                try? Wallpaper.set(URL(fileURLWithPath: item.file), on: screen)
                applied[screen.key] = item
            }
        }
        addToHistory(item)
        cleanUp()
    }

    private func addToHistory(_ item: Applied) {
        history = [item] + history.filter { $0.id != item.id }.prefix(Self.historyLimit - 1)
    }

    /// Saves what's on screen to "Kept" and stops the schedule.
    func keepCurrent() {
        let ids = Set(kept.map(\.id))
        kept = current.filter { !ids.contains($0.id) }.map { var k = $0; k.date = Date(); return k } + kept
        paused = true
    }

    /// Gets a new wallpaper now; the schedule counts from this moment.
    func restartSchedule() async {
        paused = false
        await update(fresh: true)
    }

    func removeKept(_ item: Applied) {
        kept.removeAll { $0.id == item.id }
        cleanUp()
    }

    /// Copies a wallpaper to ~/Pictures/Easy Backgrounds and shows it in Finder.
    func saveToPictures(_ item: Applied) {
        do {
            NSWorkspace.shared.activateFileViewerSelecting([try Wallpaper.saveToPictures(item)])
        } catch {
            status = "Couldn't save to Pictures: \(error.localizedDescription)"
        }
    }

    private func cleanUp() {
        Wallpaper.cleanUp(keeping: Set((history + kept + applied.values + picks.flatMap(\.items)).map(\.file)))
    }

    /// First `limit` results (in sort order) that fit every screen in `screens` and download.
    private func pick(from posts: [Post], for screens: [CGSize], minFit: Double,
                      exclude: Set<String>, limit: Int) async -> [(Post, URL)] {
        var found: [(Post, URL)] = []
        for post in posts where !exclude.contains(post.id) {
            guard screens.allSatisfy({
                      Wallhaven.fit(imageW: post.width, imageH: post.height, screenW: $0.width, screenH: $0.height) >= minFit
                  }),
                  let file = try? await Wallpaper.download(post) else { continue }
            found.append((post, file))
            if found.count == limit { break }
        }
        return found
    }

    /// Cached results for `topic`, refetched when older than `maxAge`. A 429 waits a minute once.
    func posts(_ topic: String, page: Int = 1, atleast: CGSize = .zero, maxAge: TimeInterval) async throws -> [Post] {
        let key = "\(topic.lowercased())/\(Self.sort.rawValue)/\(page)/\(Int(atleast.width))x\(Int(atleast.height))"
        if let hit = cache[key], Date().timeIntervalSince(hit.date) < maxAge { return hit.posts }
        let fetch = { try await Wallhaven.fetch(topic: topic, sort: Self.sort, page: page, atleast: atleast) }
        let posts: [Post]
        do {
            posts = try await fetch()
        } catch is RateLimited {
            try await waitForWallhaven(61)
            posts = try await fetch()
        }
        cache[key] = (Date(), posts)
        return posts
    }

    private func waitForWallhaven(_ seconds: Double) async throws {
        let until = Date().addingTimeInterval(seconds)
        waitUntil = max(waitUntil ?? until, until)
        defer { if waitUntil == until { waitUntil = nil } }
        try await Task.sleep(for: .seconds(seconds))
    }

    /// Asks GitHub at most once a day (once an hour after a network error).
    private func checkForUpdate() async {
        guard UserDefaults.standard.bool(forKey: "checkForUpdates"),
              Date().timeIntervalSince(lastUpdateCheck) > 24 * 3600 else { return }
        lastUpdateCheck = Date()
        do {
            try await fetchUpdate()
        } catch is URLError {
            lastUpdateCheck = Date().addingTimeInterval(-23 * 3600)
        } catch {} // e.g. no release published yet
    }

    /// "Check Now" in Settings: asks GitHub right away, even with daily checks off.
    func checkForUpdateNow() async -> String {
        lastUpdateCheck = Date()
        do {
            try await fetchUpdate()
            return availableUpdate.map { "Easy Backgrounds \($0.version) is available." } ?? "Easy Backgrounds is up to date."
        } catch let error as URLError {
            return error.localizedDescription
        } catch {
            return "Couldn't find a release on GitHub."
        }
    }

    func showReleaseNotes() {
        showingReleaseNotes = true
        dismissUpdateNotice()
    }

    /// The popup closed: the "updated" notice has been seen.
    func popupClosed() {
        showingReleaseNotes = false
        if justUpdated { dismissUpdateNotice() }
    }

    private func dismissUpdateNotice() {
        justUpdated = false
        UserDefaults.standard.set(Release.current, forKey: "notesSeenVersion")
    }

    private func fetchUpdate() async throws {
        guard let current = Release.current else { return } // not running from the app bundle
        let latest = try await Release.latest()
        availableUpdate = Release.isNewer(latest.version, than: current) ? latest : nil
    }

    private func tick() {
        Task { await checkForUpdate() }
        guard !busy, !paused, let next = nextUpdate, Date() >= next else { return }
        if let retryAfter, Date() < retryAfter { return }
        Task { await update(fresh: true) }
    }

    private func reapply() {
        for screen in NSScreen.screens {
            guard let a = applied[screen.key], FileManager.default.fileExists(atPath: a.file),
                  NSWorkspace.shared.desktopImageURL(for: screen)?.path != a.file else { continue }
            try? Wallpaper.set(URL(fileURLWithPath: a.file), on: screen)
        }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}

extension String {
    /// "a, b,c" → ["a", "b", "c"]
    var commaList: [String] {
        split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
