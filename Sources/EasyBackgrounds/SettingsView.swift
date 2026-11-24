import ServiceManagement
import SwiftUI

struct SettingsTab: View {
    /// Passes every good (≥ screen-resolution) 16:9, 16:10 or 3:2 image on common screens;
    /// 16:9 on a 16:10 MacBook is ~87 %, a 3:2 photo on a 16:9 screen ~84 %.
    static let safeFit = 0.8

    @EnvironmentObject private var model: AppModel
    @AppStorage("topics") private var topics = Wallhaven.defaultTopics.joined(separator: ",")
    @AppStorage("selectedTopics") private var selectedTopics = Wallhaven.defaultTopics.joined(separator: ",")
    @AppStorage("sort") private var sort = Sort.new.rawValue
    @AppStorage("minFit") private var minFit = SettingsTab.safeFit
    @AppStorage("sameOnAllScreens") private var sameOnAllScreens = true
    @AppStorage("pickCount") private var pickCount = 3
    @AppStorage("frequency") private var frequency = Frequency.daily.rawValue
    @AppStorage("updateMinutes") private var updateMinutes = 9 * 60
    @AppStorage("weekday") private var weekday = 2
    @AppStorage("checkForUpdates") private var checkForUpdates = true
    @State private var newTopic = ""
    @State private var topicMessage = ""
    @State private var checking = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError = ""
    @State private var checkingUpdate = false
    @State private var updateMessage = ""

    var body: some View {
        Form {
            topicSection
            fitSection
            scheduleSection
        }
        .formStyle(.grouped)
    }

    // MARK: Topics

    private var topicSection: some View {
        Section {
            ForEach(topics.commaList, id: \.self) { name in
                HStack {
                    Toggle(name, isOn: selected(name)).toggleStyle(.checkbox)
                    Spacer()
                    Button { remove(name) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help("Remove \(name)")
                }
            }
            HStack {
                TextField("Add", text: $newTopic, prompt: Text("Add a topic, e.g. mountains"))
                    .labelsHidden()
                    .onSubmit { add(newTopic) }
                Menu("Popular") {
                    ForEach(Wallhaven.popularTopics.filter { !contains($0) }, id: \.self) { name in
                        Button(name) { add(name) }
                    }
                }
                .fixedSize()
                .disabled(checking)
                Button("Add") { add(newTopic) }.disabled(checking || newTopic.isEmpty)
            }
            if !topicMessage.isEmpty { Text(topicMessage).font(.caption).foregroundStyle(.secondary) }
            Picker("Pick from", selection: $sort) {
                ForEach(Sort.allCases) { Text($0.label).tag($0.rawValue) }
            }
        } header: {
            Text("Topics")
        } footer: {
            Text(sort == Sort.new.rawValue
                 ? "Easy Backgrounds picks the newest fitting wallpaper from Wallhaven, taking turns between the selected topics."
                 : "Easy Backgrounds picks the most popular fitting wallpaper from Wallhaven, taking turns between the selected topics.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func contains(_ name: String) -> Bool {
        topics.commaList.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func selected(_ name: String) -> Binding<Bool> {
        Binding(get: { selectedTopics.commaList.contains(name) }, set: { on in
            selectedTopics = (selectedTopics.commaList.filter { $0 != name } + (on ? [name] : [])).joined(separator: ",")
        })
    }

    private func remove(_ name: String) {
        topics = topics.commaList.filter { $0 != name }.joined(separator: ",")
        selected(name).wrappedValue = false
    }

    /// Adds a topic after checking that Wallhaven has wallpapers for it.
    private func add(_ raw: String) {
        let name = raw.replacingOccurrences(of: ",", with: " ").trimmingCharacters(in: .whitespaces) // commas separate the stored list
        guard (1...50).contains(name.count) else { topicMessage = "A topic is a word or short phrase."; return }
        guard !contains(name) else { topicMessage = "\"\(name)\" is already in the list."; return }
        checking = true
        topicMessage = "Checking \"\(name)\"…"
        Task {
            defer { checking = false }
            do {
                guard try await !model.posts(name, maxAge: 30 * 60).isEmpty else {
                    topicMessage = "Wallhaven has no wallpapers for \"\(name)\"."
                    return
                }
                topics = (topics.commaList + [name]).joined(separator: ",")
                selected(name).wrappedValue = true
                if raw == newTopic { newTopic = "" }
                topicMessage = "Added \"\(name)\"."
            } catch {
                topicMessage = error.localizedDescription
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
            Toggle("Same wallpaper on all screens", isOn: $sameOnAllScreens)
            Text(sameOnAllScreens ? "The image must fit every connected screen." : "Each screen gets its own best-fitting image.")
                .font(.caption).foregroundStyle(.secondary)
            Stepper("Images per update: \(pickCount)", value: $pickCount, in: 1...5)
            Text(pickCount == 1 ? "Only the wallpaper itself is downloaded." : "The best \(pickCount) are downloaded, so you can switch between them on the Now tab right away.")
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
            Text("Asks GitHub once a day whether a newer version exists.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Version \(Release.current ?? "unknown")") {
                HStack {
                    Button("Release Notes") { model.showReleaseNotes() }
                    Button(checkingUpdate ? "Checking…" : "Check Now") {
                        checkingUpdate = true
                        Task {
                            updateMessage = await model.checkForUpdateNow()
                            checkingUpdate = false
                        }
                    }
                    .disabled(checkingUpdate)
                }
            }
            if !updateMessage.isEmpty { Text(updateMessage).font(.caption) }
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
}
