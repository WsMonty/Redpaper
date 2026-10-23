import SwiftUI

/// The menu bar popup: Now / History / Settings.
struct PopupView: View {
    @EnvironmentObject private var model: AppModel
    enum Tab: String, CaseIterable { case now = "Now", history = "History", settings = "Settings" }
    @State private var tab = Tab.now

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            Divider()
            if model.justUpdated, let version = Release.current {
                Label {
                    HStack {
                        Text("Redpaper was updated to \(version).")
                        Button("What's new") { model.showReleaseNotes() }
                            .buttonStyle(.link)
                    }
                } icon: { Image(systemName: "sparkles") }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 8)
                Divider()
            }
            Group {
                switch tab {
                case .now: NowTab()
                case .history: HistoryTab()
                case .settings: SettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if let until = model.waitUntil {
                Divider()
                Label {
                    Text("Reddit allows about one request a minute. Continuing in \(Text(until, style: .timer))")
                        .monospacedDigit()
                } icon: { Image(systemName: "hourglass") }
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            if let update = model.availableUpdate {
                Divider()
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Redpaper \(update.version) is available.")
                            Link("What's new", destination: update.html_url)
                        }
                        Text("To update, run `git pull && ./deploy.sh` in your Redpaper folder.")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } icon: { Image(systemName: "arrow.down.circle") }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            Divider()
            HStack {
                Spacer()
                Button("Quit Redpaper") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 360, height: 540)
        .overlay {
            if model.showingReleaseNotes { ReleaseNotesView().background(.background) }
        }
        .background(RightAligner())
        // The popup is the app's only window, so losing key means it closed.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            model.popupClosed()
        }
    }
}

private struct ReleaseNotesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Release Notes").font(.headline)
                Spacer()
                Button("Done") { model.showingReleaseNotes = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if Release.notes.isEmpty {
                        Text("No release notes in this build.").foregroundStyle(.secondary)
                    }
                    ForEach(Release.notes, id: \.version) { release in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Version \(release.version)").font(.headline)
                            Text((try? AttributedString(markdown: release.notes, options: .init(
                                interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(release.notes))
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }
}

/// MenuBarExtra puts the popup's left edge under the icon; the icon sits near the right of
/// the screen, so line the popup's right edge up with the icon instead.
private struct RightAligner: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { View() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class View: NSView {
        private var observer: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer.map(NotificationCenter.default.removeObserver)
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { _ in MainActor.assumeIsolated { Self.align(window) } }
            Self.align(window)
        }

        private static func align(_ popup: NSWindow) {
            // Matches the private NSStatusBarWindow class; if it's ever renamed we just skip.
            guard let screen = popup.screen,
                  let icon = NSApp.windows
                      .filter({ $0.className == "NSStatusBarWindow" && $0.screen == screen })
                      .min(by: { abs($0.frame.minX - popup.frame.minX) < abs($1.frame.minX - popup.frame.minX) })
            else { return }
            let x = max(screen.visibleFrame.minX, icon.frame.maxX - popup.frame.width)
            popup.setFrameOrigin(NSPoint(x: x, y: popup.frame.minY))
        }
    }
}

private struct NowTab: View {
    @EnvironmentObject private var model: AppModel
    // Held only so "Next update" redraws when these change.
    @AppStorage("frequency") private var frequency = Frequency.daily.rawValue
    @AppStorage("updateMinutes") private var updateMinutes = 9 * 60
    @AppStorage("weekday") private var weekday = 2
    @AppStorage("lastUpdate") private var lastUpdate = 0.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.current.isEmpty {
                    placeholder(model.busy ? "Finding a wallpaper…" : "No wallpaper yet")
                }
                ForEach(model.current, id: \.file) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Thumbnail(path: item.file)
                        Text(item.title).font(.headline).lineLimit(2)
                        if let url = URL(string: item.permalink) {
                            Link(destination: url) {
                                Label("r/\(item.subreddit)", systemImage: "arrow.up.right.square")
                            }
                            .font(.callout)
                        }
                    }
                }
                if model.paused {
                    Label("Kept. The schedule is paused.", systemImage: "pin.fill")
                        .font(.callout).foregroundStyle(.secondary)
                    Button { Task { await model.restartSchedule() } } label: {
                        Label(model.busy ? "Updating…" : "Restart Schedule", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.busy)
                    Text("Gets a new wallpaper now and schedules from then on.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button { Task { await model.update() } } label: {
                            Label(model.busy ? "Updating…" : "Next Wallpaper", systemImage: "forward.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("n")
                        Button { model.keepCurrent() } label: {
                            Label("Keep", systemImage: "pin").frame(maxWidth: .infinity)
                        }
                        .help("Keep this wallpaper and pause the schedule")
                        .disabled(model.current.isEmpty)
                    }
                    .controlSize(.large)
                    .disabled(model.busy)
                    Text(nextText).font(.caption).foregroundStyle(.secondary)
                }
                if !model.status.isEmpty {
                    Text(model.status).font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(14)
        }
    }

    private var nextText: String {
        guard let next = model.nextUpdate else { return "Automatic updates are off." }
        return "Next update: " + (next <= Date() ? "now" : next.formatted(date: .abbreviated, time: .shortened))
    }
}

private struct HistoryTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.history.isEmpty && model.kept.isEmpty {
            ContentUnavailableView("No history yet", systemImage: "clock",
                                   description: Text("Wallpapers you've had will show up here."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Click one to use it until the next scheduled update. Right-click to save it to Pictures.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !model.kept.isEmpty {
                        section("Kept wallpapers", model.kept, removable: true)
                    }
                    if !model.history.isEmpty {
                        section("Recent (last \(AppModel.historyLimit))", model.history, removable: false)
                    }
                }
                .padding(14)
            }
        }
    }

    private func section(_ title: String, _ items: [Applied], removable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).padding(.top, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 12) {
                ForEach(items, id: \.id) { item in
                    Button { model.restore(item) } label: { cell(item) }
                        .buttonStyle(.plain)
                        .help(item.title)
                        .contextMenu {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.file)])
                            }
                            Button("Save to Pictures") { model.saveToPictures(item) }
                            if removable {
                                Divider()
                                Button("Remove from Kept") { model.removeKept(item) }
                            }
                        }
                }
            }
        }
    }

    private func cell(_ item: Applied) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Thumbnail(path: item.file)
                .overlay(alignment: .topTrailing) {
                    if model.current.contains(where: { $0.id == item.id }) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(5)
                    }
                }
            Text(item.title).font(.caption).lineLimit(1)
            Text("r/\(item.subreddit) · \(item.date.formatted(.relative(presentation: .named)))")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

private func placeholder(_ text: String) -> some View {
    Color.secondary.opacity(0.15)
        .aspectRatio(16 / 10, contentMode: .fit)
        .overlay { Text(text).foregroundStyle(.secondary) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
}

struct Thumbnail: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        Color.secondary.opacity(0.15)
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                if let image { Image(nsImage: image).resizable().scaledToFill() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .task(id: path) { image = await Wallpaper.thumbnail(path) }
    }
}
