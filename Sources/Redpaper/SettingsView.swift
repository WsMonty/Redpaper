import ServiceManagement
import SwiftUI

struct SettingsTab: View {
    /// Passes every good (≥ screen-resolution) 16:9, 16:10 or 3:2 image on common screens;
    /// 16:9 on a 16:10 MacBook is ~87 %, a 3:2 photo on a 16:9 screen ~84 %.
    static let safeFit = 0.8

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var auth: Auth
    @AppStorage("subreddits") private var subreddits = "wallpapers"
    @AppStorage("customSubreddits") private var customSubreddits = ""
    @AppStorage("minFit") private var minFit = SettingsTab.safeFit
    @AppStorage("skipNSFW") private var skipNSFW = true
    @AppStorage("sameOnAllScreens") private var sameOnAllScreens = true
    @AppStorage("frequency") private var frequency = Frequency.daily.rawValue
    @AppStorage("updateMinutes") private var updateMinutes = 9 * 60
    @AppStorage("weekday") private var weekday = 2
    @AppStorage("checkForUpdates") private var checkForUpdates = true
    @State private var newSub = ""
    @State private var subMessage = ""
    @State private var checking = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError = ""
    @State private var accountError = ""
    @State private var signingIn = false

    var body: some View {
        Form {
            subredditSection
            fitSection
            scheduleSection
            accountSection
        }
        .formStyle(.grouped)
    }

    // MARK: Subreddits

    private var subredditSection: some View {
        Section {
            ForEach(Reddit.presets + customSubreddits.commaList, id: \.self) { name in
                HStack {
                    Toggle("r/\(name)", isOn: selected(name)).toggleStyle(.checkbox)
                    Spacer()
                    if !Reddit.presets.contains(name) {
                        Button { remove(name) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Remove r/\(name)")
                    }
                }
            }
            HStack {
                TextField("Add", text: $newSub, prompt: Text("Add a subreddit, e.g. ImaginaryLandscapes"))
                    .labelsHidden()
                    .onSubmit(add)
                Button("Add", action: add).disabled(checking || newSub.isEmpty)
            }
            if !subMessage.isEmpty { Text(subMessage).font(.caption).foregroundStyle(.secondary) }
        } header: {
            Text("Subreddits")
        } footer: {
            Text("Redpaper picks the newest fitting image across all selected subreddits.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func selected(_ name: String) -> Binding<Bool> {
        Binding(get: { subreddits.commaList.contains(name) }, set: { on in
            subreddits = (subreddits.commaList.filter { $0 != name } + (on ? [name] : [])).joined(separator: ",")
        })
    }

    private func remove(_ name: String) {
        customSubreddits = customSubreddits.commaList.filter { $0 != name }.joined(separator: ",")
        selected(name).wrappedValue = false
    }

    private func add() {
        let name = newSub.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "^/?r/", with: "", options: [.regularExpression, .caseInsensitive])
        guard Reddit.isValidName(name) else { subMessage = "That's not a valid subreddit name."; return }
        guard !(Reddit.presets + customSubreddits.commaList).contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
        else { subMessage = "r/\(name) is already in the list."; return }
        checking = true
        subMessage = "Checking r/\(name)…"
        Task {
            defer { checking = false }
            do {
                let posts = try await model.posts([name], maxAge: 30 * 60)
                customSubreddits = (customSubreddits.commaList + [name]).joined(separator: ",")
                selected(name).wrappedValue = true
                newSub = ""
                subMessage = posts.isEmpty
                    ? "Added r/\(name), but its newest posts contain no images."
                    : "Added r/\(name) (\(posts.count) image posts found)."
            } catch {
                subMessage = error.localizedDescription
            }
        }
    }

    // MARK: Fit

    private var fitSection: some View {
        Section("Fit") {
            Slider(value: $minFit, in: 0.5...1, step: 0.05) {
                Text(verbatim: "Minimum fit: \(Int((minFit * 100).rounded())) %")
            }
            Text(verbatim: "How closely an image must match each screen's shape and resolution. \(Int(Self.safeFit * 100)) % (the default) accepts every good image.")
                .font(.caption).foregroundStyle(.secondary)
            if minFit > Self.safeFit + 0.001 {
                Label("Above \(Int(Self.safeFit * 100)) %, it will probably be harder to find an image, especially on MacBook screens (16:10), where most wallpapers (16:9) top out at 87 %.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Toggle("Skip NSFW posts", isOn: $skipNSFW)
            Toggle("Same wallpaper on all screens", isOn: $sameOnAllScreens)
            Text(sameOnAllScreens ? "The image must fit every connected screen." : "Each screen gets its own best-fitting image.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Schedule

    private var scheduleSection: some View {
        Section("Schedule") {
            Picker("Change wallpaper", selection: $frequency) {
                ForEach(Frequency.allCases) { Text($0.label).tag($0.rawValue) }
            }
            if frequency == Frequency.weekly.rawValue {
                Picker("On", selection: $weekday) {
                    ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                }
            }
            if frequency == Frequency.daily.rawValue || frequency == Frequency.weekly.rawValue {
                DatePicker("At", selection: time, displayedComponents: .hourAndMinute)
            }
            Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { on in
                do {
                    try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    loginError = ""
                } catch {
                    loginError = error.localizedDescription
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }))
            if !loginError.isEmpty { Text(loginError).font(.caption).foregroundStyle(.red) }
            Toggle("Check for updates", isOn: $checkForUpdates)
            Text("Asks GitHub once a day whether a newer version exists. This is version \(Release.current ?? "unknown").")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: updateMinutes / 60, minute: updateMinutes % 60, second: 0, of: Date())! },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                updateMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }

    // MARK: Account

    private var accountSection: some View {
        Section("Reddit account") {
            if !Auth.isConfigured {
                Text("Not needed: Redpaper uses Reddit's public feed. Sign-in needs a Reddit-approved API app; once you have one, paste its client ID into Auth.swift and rebuild.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if auth.signedIn {
                LabeledContent("Signed in as", value: auth.username.map { "u/\($0)" } ?? "Reddit user")
                Button("Sign Out") { auth.signOut() }
            } else {
                Button(signingIn ? "Waiting for Reddit…" : "Sign in with Reddit") {
                    signingIn = true
                    accountError = ""
                    Task {
                        do { try await auth.signIn() }
                        catch is CancellationError {}
                        catch { accountError = error.localizedDescription }
                        signingIn = false
                    }
                }
                .disabled(signingIn)
            }
            if !accountError.isEmpty { Text(accountError).font(.caption).foregroundStyle(.red) }
        }
    }
}
