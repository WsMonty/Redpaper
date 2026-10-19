import AppKit
import SwiftUI

@main
struct RedpaperApp: App {
    @StateObject private var model = AppModel()

    init() {
        if CommandLine.arguments.contains("--selftest") {
            Reddit.selfTest()
            Schedule.selfTest()
            Release.selfTest()
            print("selftest ok")
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopupView().environmentObject(model).environmentObject(model.auth)
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
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/WsMonty/Redpaper/releases/latest")!)
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
    }
}

@MainActor
final class AppModel: ObservableObject {
    let auth = Auth()
    @Published private(set) var busy = false
    @Published private(set) var status = ""
    /// Set while waiting out Reddit's rate limit, so the popup can count down.
    @Published private(set) var waitUntil: Date?
    /// What's on each screen, keyed by display id.
    @Published private(set) var applied: [String: Applied] = AppModel.load("applied") ?? [:] {
        didSet { save(applied, "applied") }
    }
    /// The last `historyLimit` wallpapers, newest first. Older ones are deleted from disk.
    @Published private(set) var history: [Applied] = AppModel.load("history") ?? [] {
        didSet { save(history, "history") }
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
    static let historyLimit = 7
    private var lastUpdateCheck = Date.distantPast
    private var retryAfter: Date?
    private var timer: Timer?
    private var cache: [String: (date: Date, posts: [Post])] = [:]
    private var lastFetch = Date.distantPast
    private var probedSizes: [String: CGSize] = [:]
    /// Post ids already shown (or skipped), newest last, so "Next" and scheduled updates never repeat.
    private var seen = UserDefaults.standard.stringArray(forKey: "seen") ?? [] {
        didSet { UserDefaults.standard.set(Array(seen.suffix(1000)), forKey: "seen") }
    }
    /// Index into the selected subreddits whose turn is next.
    private var rotation = UserDefaults.standard.integer(forKey: "rotation") {
        didSet { UserDefaults.standard.set(rotation, forKey: "rotation") }
    }

    init() {
        UserDefaults.standard.register(defaults: [
            "subreddits": "wallpapers", "customSubreddits": "", "minFit": SettingsTab.safeFit, "skipNSFW": true, "sameOnAllScreens": true,
            "frequency": Frequency.daily.rawValue, "updateMinutes": 9 * 60, "weekday": 2, "checkForUpdates": true,
        ])
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

    /// Selected subreddits, stored comma-separated (AppStorage can't hold arrays).
    static var subreddits: [String] { (UserDefaults.standard.string(forKey: "subreddits") ?? "").commaList }

    static var sort: Sort { Sort(rawValue: UserDefaults.standard.string(forKey: "sort") ?? "") ?? .new }

    var nextUpdate: Date? {
        let d = UserDefaults.standard
        return Schedule.next(
            after: Date(timeIntervalSince1970: d.double(forKey: "lastUpdate")),
            Frequency(rawValue: d.string(forKey: "frequency") ?? "") ?? .daily,
            minutes: d.integer(forKey: "updateMinutes"),
            weekday: d.integer(forKey: "weekday"))
    }

    /// Shows a new wallpaper, taking turns between the selected subreddits. `fresh` refetches
    /// posts (scheduled runs); otherwise the cached list is reused, so "Next" usually costs no request.
    func update(fresh: Bool = false) async {
        guard !busy else { return }
        busy = true
        status = ""
        defer { busy = false }

        let d = UserDefaults.standard
        let subs = Self.subreddits
        guard !subs.isEmpty else { status = "Select at least one subreddit in Settings."; return }
        let minFit = d.double(forKey: "minFit")
        let skipNSFW = d.bool(forKey: "skipNSFW")
        let maxAge: TimeInterval = fresh ? 60 : 30 * 60
        do {
            let combined = try await posts(subs, maxAge: maxAge)
            var exclude = Set(seen)
            var missed = 0
            // One group with every screen (same image everywhere), or one group per screen.
            let groups = d.bool(forKey: "sameOnAllScreens") ? [NSScreen.screens] : NSScreen.screens.map { [$0] }
            for group in groups {
                let sizes = group.map(\.pixelSize)
                var picked: (Post, URL)?
                // Try the subreddit whose turn it is, then the following ones.
                for step in 0..<subs.count where picked == nil {
                    let i = (rotation + step) % subs.count
                    let mine = { (posts: [Post]) in posts.filter { $0.subreddit.caseInsensitiveCompare(subs[i]) == .orderedSame } }
                    picked = await pick(from: mine(combined), for: sizes, minFit: minFit,
                                        skipNSFW: skipNSFW, exclude: exclude)
                    // Busy subreddits crowd quiet ones out of the combined feed: fetch the quiet one alone.
                    if picked == nil, subs.count > 1, let own = try? await posts([subs[i]], maxAge: maxAge) {
                        picked = await pick(from: mine(own), for: sizes, minFit: minFit,
                                            skipNSFW: skipNSFW, exclude: exclude)
                    }
                    if picked != nil { rotation = (i + 1) % subs.count }
                }
                guard let (post, file) = picked else { missed += 1; continue }
                let shown = Applied(id: post.id, file: file.path, title: post.title,
                                    permalink: post.permalink, subreddit: post.subreddit)
                for screen in group {
                    try Wallpaper.set(file, on: screen)
                    applied[screen.key] = shown
                }
                history = [shown] + history.filter { $0.id != post.id }.prefix(Self.historyLimit - 1)
                exclude.insert(post.id)
                seen.append(post.id)
            }
            cleanUp()
            d.set(Date().timeIntervalSince1970, forKey: "lastUpdate")
            retryAfter = nil
            if missed > 0 {
                status = "No new image with ≥ \(Int((minFit * 100).rounded())) % fit in \(Self.sort == .new ? "the newest" : "the top") posts"
                    + (groups.count > 1 ? " for \(missed) screen(s)." : ".")
            }
        } catch {
            status = error.localizedDescription
            // Offline (e.g. just woke up): try again next minute. Reddit trouble: back off.
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
        for screen in NSScreen.screens {
            try? Wallpaper.set(URL(fileURLWithPath: item.file), on: screen)
            applied[screen.key] = item
        }
        status = ""
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

    /// Copies a wallpaper to ~/Pictures/Redpaper and shows it in Finder.
    func saveToPictures(_ item: Applied) {
        do {
            NSWorkspace.shared.activateFileViewerSelecting([try Wallpaper.saveToPictures(item)])
        } catch {
            status = "Couldn't save to Pictures: \(error.localizedDescription)"
        }
    }

    private func cleanUp() {
        Wallpaper.cleanUp(keeping: Set((history + kept + applied.values).map(\.file)))
    }

    /// First post (newest first) that fits every screen in `screens` and downloads.
    /// Sizes missing from titles are probed lazily.
    private func pick(from posts: [Post], for screens: [CGSize], minFit: Double, skipNSFW: Bool,
                      exclude: Set<String>) async -> (Post, URL)? {
        for post in posts where !(skipNSFW && post.nsfw) && !exclude.contains(post.id) {
            var size = post.width.flatMap { w in post.height.map { CGSize(width: w, height: $0) } } ?? probedSizes[post.id]
            if size == nil {
                size = await Wallpaper.probeSize(post.imageURL) ?? .zero // .zero: don't probe again
                probedSizes[post.id] = size
            }
            guard let size, screens.allSatisfy({
                      Reddit.fit(imageW: size.width, imageH: size.height, screenW: $0.width, screenH: $0.height) >= minFit
                  }),
                  let file = try? await Wallpaper.download(post) else { continue }
            return (post, file)
        }
        return nil
    }

    /// Cached post list for `subs`, refetched when older than `maxAge`. Signed out, requests are spaced
    /// ≥ 61 s apart (Reddit's RSS limit is ~1/min) and a 429 waits for the reset once.
    func posts(_ subs: [String], maxAge: TimeInterval) async throws -> [Post] {
        let key = subs.map { $0.lowercased() }.sorted().joined(separator: "+") + "/" + Self.sort.rawValue
        if let hit = cache[key], Date().timeIntervalSince(hit.date) < maxAge { return hit.posts }
        if !auth.signedIn {
            // Reserve the next slot before waiting, so concurrent callers queue up instead of colliding.
            let slot = max(Date(), lastFetch.addingTimeInterval(61))
            lastFetch = slot
            if slot > Date() { try await waitForReddit(slot.timeIntervalSinceNow) }
        }
        lastFetch = max(lastFetch, Date())
        let posts: [Post]
        do {
            posts = try await fetchPosts(subs)
        } catch let limit as RateLimited {
            try await waitForReddit(limit.reset + 1)
            lastFetch = Date()
            posts = try await fetchPosts(subs)
        }
        cache[key] = (Date(), posts)
        return posts
    }

    private func waitForReddit(_ seconds: Double) async throws {
        let until = Date().addingTimeInterval(seconds)
        waitUntil = max(waitUntil ?? until, until)
        defer { if waitUntil == until { waitUntil = nil } }
        try await Task.sleep(for: .seconds(seconds))
    }

    /// Uses the signed-in API when available, the public feed otherwise.
    private func fetchPosts(_ subs: [String]) async throws -> [Post] {
        do {
            return try await Reddit.fetch(subs: subs, sort: Self.sort, token: auth.accessToken())
        } catch is Unauthorized where auth.signedIn {
            return try await Reddit.fetch(subs: subs, sort: Self.sort, token: auth.refresh())
        }
    }

    /// Asks GitHub at most once a day (once an hour after a network error).
    private func checkForUpdate() async {
        guard UserDefaults.standard.bool(forKey: "checkForUpdates"), let current = Release.current else {
            availableUpdate = nil
            return
        }
        guard Date().timeIntervalSince(lastUpdateCheck) > 24 * 3600 else { return }
        lastUpdateCheck = Date()
        do {
            let latest = try await Release.latest()
            availableUpdate = Release.isNewer(latest.version, than: current) ? latest : nil
        } catch is URLError {
            lastUpdateCheck = Date().addingTimeInterval(-23 * 3600)
        } catch {} // e.g. no release published yet
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
