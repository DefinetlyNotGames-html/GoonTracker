import SwiftUI
import LocalAuthentication
import UserNotifications
import PhotosUI
import Charts

// MARK: - App
@main
struct GoonTrackerApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(store.accent)
                .preferredColorScheme(store.appearance.colorScheme)
        }
    }
}

// MARK: - Theme
enum AppearanceMode: Int, CaseIterable, Identifiable {
    case system, light, dark
    var id: Int { rawValue }
    var label: String { switch self { case .system: return "System"; case .light: return "Light"; case .dark: return "Dark" } }
    var colorScheme: ColorScheme? { switch self { case .system: return nil; case .light: return .light; case .dark: return .dark } }
}

let accentPalette: [(name: String, color: Color)] = [
    ("Orange", Color(red: 1.0, green: 0.48, blue: 0.27)),
    ("Teal", Color(red: 0.18, green: 0.77, blue: 0.71)),
    ("Pink", Color(red: 0.96, green: 0.42, blue: 0.55)),
    ("Blue", Color(red: 0.25, green: 0.55, blue: 0.95)),
    ("Green", Color(red: 0.30, green: 0.75, blue: 0.45))
]

extension View {
    func card() -> some View {
        padding(20).frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    func appBG(_ accent: Color) -> some View {
        background(
            LinearGradient(colors: [accent.opacity(0.16), Color(.systemBackground), accent.opacity(0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        )
    }
}

func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

let quotes = [
    "Discipline is choosing what you want most over what you want now.",
    "Small wins compound. Today counts.",
    "You don't have to be perfect, just consistent.",
    "Every clean day rewires the habit.",
    "Progress, not perfection.",
    "Urges pass. Fifteen minutes is often all it takes.",
    "You're building the version of you that keeps promises.",
    "One day at a time is still a plan.",
    "Slip-ups are data, not failure.",
    "Future you is thankful for today's choice."
]

struct Achievement: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let target: Int
    let kind: Kind
    enum Kind { case totalDays, bestStreak, cleanCurrent }
}

let achievements: [Achievement] = [
    .init(title: "3 Day Streak", icon: "flame", target: 3, kind: .bestStreak),
    .init(title: "1 Week Streak", icon: "flame.fill", target: 7, kind: .bestStreak),
    .init(title: "2 Week Streak", icon: "bolt.fill", target: 14, kind: .bestStreak),
    .init(title: "1 Month Streak", icon: "star.fill", target: 30, kind: .bestStreak),
    .init(title: "100 Day Streak", icon: "crown.fill", target: 100, kind: .bestStreak),
    .init(title: "7 Days Tracked", icon: "checkmark.circle", target: 7, kind: .totalDays),
    .init(title: "30 Days Tracked", icon: "checkmark.seal", target: 30, kind: .totalDays),
    .init(title: "100 Days Tracked", icon: "rosette", target: 100, kind: .totalDays)
]

// MARK: - Store
final class Store: ObservableObject {
    private let d = UserDefaults.standard
    private let cal = Calendar.current

    @Published var name: String { didSet { d.set(name, forKey: "name") } }
    @Published var entries: [String: Int] { didSet { d.set(entries, forKey: "entries") } }
    @Published var notes: [String: String] { didSet { d.set(notes, forKey: "notes") } }
    @Published var lockOn: Bool { didSet { d.set(lockOn, forKey: "lockOn") } }
    @Published var reminderOn: Bool { didSet { d.set(reminderOn, forKey: "reminderOn"); updateReminder() } }
    @Published var weeklyGoal: Int { didSet { d.set(weeklyGoal, forKey: "weeklyGoal") } }
    @Published var appearanceRaw: Int { didSet { d.set(appearanceRaw, forKey: "appearance") } }
    @Published var accentIndex: Int { didSet { d.set(accentIndex, forKey: "accentIndex") } }
    @Published var photoFilenames: [String] { didSet { d.set(photoFilenames, forKey: "photoFilenames") } }
    let startDate: Date

    var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .system }
    var accent: Color { accentPalette[min(max(accentIndex, 0), accentPalette.count - 1)].color }

    init() {
        name = d.string(forKey: "name") ?? ""
        entries = d.dictionary(forKey: "entries") as? [String: Int] ?? [:]
        notes = d.dictionary(forKey: "notes") as? [String: String] ?? [:]
        lockOn = d.bool(forKey: "lockOn")
        reminderOn = d.bool(forKey: "reminderOn")
        weeklyGoal = d.object(forKey: "weeklyGoal") as? Int ?? 7
        appearanceRaw = d.object(forKey: "appearance") as? Int ?? 0
        accentIndex = d.object(forKey: "accentIndex") as? Int ?? 0
        photoFilenames = d.stringArray(forKey: "photoFilenames") ?? []
        if let s = d.object(forKey: "start") as? Date {
            startDate = s
        } else {
            let n = Calendar.current.startOfDay(for: Date())
            d.set(n, forKey: "start")
            startDate = n
        }
    }

    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func key(_ date: Date) -> String { fmt.string(from: date) }

    func count(_ date: Date) -> Int { entries[Store.key(date)] ?? 0 }
    func answered(_ date: Date) -> Bool { entries[Store.key(date)] != nil }
    func set(_ date: Date, _ n: Int) { entries[Store.key(date)] = max(0, n) }
    func clear(_ date: Date) { entries[Store.key(date)] = nil; notes[Store.key(date)] = nil }
    func note(_ date: Date) -> String { notes[Store.key(date)] ?? "" }
    func setNote(_ date: Date, _ text: String) { notes[Store.key(date)] = text }

    var total: Int { entries.values.reduce(0, +) }
    var daysTracked: Int { entries.count }

    var thisMonth: Int {
        let p = String(Store.key(Date()).prefix(7))
        return entries.filter { $0.key.hasPrefix(p) }.values.reduce(0, +)
    }

    var thisWeek: Int {
        var sum = 0
        for i in 0..<7 {
            let d = cal.date(byAdding: .day, value: -i, to: Date())!
            sum += count(d)
        }
        return sum
    }

    var lastSevenDays: [(label: String, value: Int)] {
        (0..<7).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: Date())!
            let f = DateFormatter(); f.dateFormat = "E"
            return (f.string(from: d), count(d))
        }
    }

    private var begin: Date {
        let earliest = entries.keys.compactMap { Store.fmt.date(from: $0) }.min()
        return min(startDate, earliest ?? startDate)
    }

    var daysClean: Int {
        var day = cal.startOfDay(for: Date())
        var n = 0
        while day >= begin {
            if count(day) > 0 { break }
            n += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return n
    }

    var bestStreak: Int {
        var day = begin
        let today = cal.startOfDay(for: Date())
        var run = 0, best = 0
        while day <= today {
            if count(day) > 0 { run = 0 } else { run += 1; best = max(best, run) }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return best
    }

    func isUnlocked(_ a: Achievement) -> Bool {
        switch a.kind {
        case .bestStreak: return bestStreak >= a.target
        case .totalDays: return daysTracked >= a.target
        case .cleanCurrent: return daysClean >= a.target
        }
    }

    func resetAll() {
        entries = [:]
        notes = [:]
        d.set(Calendar.current.startOfDay(for: Date()), forKey: "start")
    }

    func exportCSV() -> String {
        var lines = ["Date,Count,Note"]
        for key in entries.keys.sorted() {
            let n = notes[key]?.replacingOccurrences(of: ",", with: ";") ?? ""
            lines.append("\(key),\(entries[key] ?? 0),\(n)")
        }
        return lines.joined(separator: "\n")
    }

    // Photos - stored as JPEG files in Documents/GoonPhotos
    private var photosDir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("GoonPhotos")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func addPhoto(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        let name = UUID().uuidString + ".jpg"
        try? data.write(to: photosDir.appendingPathComponent(name))
        photoFilenames.append(name)
    }

    func loadImage(_ filename: String) -> UIImage? {
        UIImage(contentsOfFile: photosDir.appendingPathComponent(filename).path)
    }

    func deletePhoto(_ filename: String) {
        try? FileManager.default.removeItem(at: photosDir.appendingPathComponent(filename))
        photoFilenames.removeAll { $0 == filename }
    }

    func deleteAllPhotos() {
        for f in photoFilenames { try? FileManager.default.removeItem(at: photosDir.appendingPathComponent(f)) }
        photoFilenames = []
    }

    private func updateReminder() {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: ["daily"])
        guard reminderOn else { return }
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { DispatchQueue.main.async { self.reminderOn = false }; return }
            let content = UNMutableNotificationContent()
            content.title = "Check-in"
            content.body = "Time for your daily check-in"
            var comps = DateComponents(); comps.hour = 21
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            c.add(UNNotificationRequest(identifier: "daily", content: content, trigger: trigger))
        }
    }

    func authenticate(_ done: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { done(true); return }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock GoonTracker") { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }
}

// MARK: - Root
struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase
    @State private var locked = UserDefaults.standard.bool(forKey: "lockOn")

    var body: some View {
        Group {
            if store.name.isEmpty { Onboarding() }
            else if locked { LockView(locked: $locked) }
            else { MainTabs() }
        }
        .onChange(of: phase) { p in
            if p == .background && store.lockOn { locked = true }
        }
    }
}

// MARK: - Onboarding
struct Onboarding: View {
    @EnvironmentObject var store: Store
    @State private var text = ""

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("📊").font(.system(size: 64))
            Text("Welcome to GoonTracker").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("What's your name?").foregroundStyle(.secondary)
            TextField("Name", text: $text)
                .textInputAutocapitalization(.words)
                .multilineTextAlignment(.center)
                .font(.title3)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .submitLabel(.done)
            Button {
                haptic()
                store.name = text.trimmingCharacters(in: .whitespaces)
            } label: {
                Text("Continue").font(.headline).frame(maxWidth: .infinity).padding()
                    .background(store.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundColor(.white)
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            Spacer()
        }
        .padding(28)
        .appBG(store.accent)
    }
}

struct LockView: View {
    @EnvironmentObject var store: Store
    @Binding var locked: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.system(size: 48))
            Text("Locked").font(.title2.bold())
            Button("Unlock") { tryUnlock() }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBG(store.accent)
        .onAppear { tryUnlock() }
    }

    private func tryUnlock() {
        store.authenticate { ok in if ok { locked = false } }
    }
}

// MARK: - Tabs
struct MainTabs: View {
    var body: some View {
        TabView {
            Home().tabItem { Label("Today", systemImage: "house.fill") }
            CalendarTab().tabItem { Label("Calendar", systemImage: "calendar") }
            StatsTab().tabItem { Label("Stats", systemImage: "chart.bar.fill") }
            PhotosTab().tabItem { Label("Photos", systemImage: "photo.stack.fill") }
            SettingsTab().tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

// MARK: - Home
struct Home: View {
    @EnvironmentObject var s: Store

    private var todayQuote: String { quotes[Calendar.current.ordinality(of: .day, in: .year, for: Date())! % quotes.count] }

    private var status: String {
        let t = Date()
        guard s.answered(t) else { return "Not answered yet today" }
        return "Gooned \(s.count(t)) today"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text("Hey, \(s.name) 👋").font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 16) {
                        Text("Have you gooned today?")
                            .font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            answerButton("Yes", color: s.accent) {
                                s.set(Date(), s.count(Date()) + 1)
                            }
                            answerButton("No", color: .green) {
                                s.set(Date(), 0)
                            }
                        }
                        Text(status).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    }
                    .card()

                    VStack(spacing: 4) {
                        Text("\(s.total)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(s.accent)
                        Text("times total").foregroundStyle(.secondary)
                    }
                    .card()

                    HStack(spacing: 12) {
                        tile("\(s.daysClean)", "Days clean")
                        tile("\(s.bestStreak)", "Best streak")
                        tile("\(s.thisMonth)", "This month")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Quote of the day", systemImage: "quote.opening").font(.caption).foregroundStyle(s.accent)
                        Text(todayQuote).font(.subheadline.italic())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Weekly goal", systemImage: "target").font(.subheadline.bold())
                            Spacer()
                            Text("\(s.thisWeek)/\(s.weeklyGoal)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(Double(s.thisWeek), Double(s.weeklyGoal)), total: Double(s.weeklyGoal))
                            .tint(s.thisWeek > s.weeklyGoal ? .red : s.accent)
                    }
                    .card()
                }
                .padding()
            }
            .appBG(s.accent)
            .navigationTitle("GoonTracker")
        }
    }

    private func answerButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button { haptic(); action() } label: {
            Text(title).font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundColor(.white)
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 16).frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Calendar
struct CalendarTab: View {
    @EnvironmentObject var s: Store
    @State private var month = Date()
    @State private var picked: Pick?
    private let cal = Calendar.current

    struct Pick: Identifiable { let date: Date; var id: Date { date } }

    private var days: [Date?] {
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let n = cal.range(of: .day, in: .month, for: first)!.count
        let offset = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        var out = [Date?](repeating: nil, count: offset)
        for i in 0..<n { out.append(cal.date(byAdding: .day, value: i, to: first)!) }
        return out
    }

    private var weekdays: [String] {
        let sy = cal.veryShortWeekdaySymbols
        let f = cal.firstWeekday - 1
        return Array(sy[f...] + sy[..<f])
    }

    private var atCurrentMonth: Bool { cal.isDate(month, equalTo: Date(), toGranularity: .month) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Text(month.formatted(.dateTime.month(.wide).year())).font(.title3.bold())
                        Spacer()
                        Button { shift(1) } label: { Image(systemName: "chevron.right") }.disabled(atCurrentMonth)
                    }

                    HStack {
                        ForEach(Array(weekdays.enumerated()), id: \.offset) { item in
                            Text(item.element).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        }
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                        ForEach(Array(days.enumerated()), id: \.offset) { item in
                            if let d = item.element { cell(d) } else { Color.clear.frame(height: 44) }
                        }
                    }

                    HStack(spacing: 16) {
                        legend(s.accent, "Gooned")
                        legend(Color.green.opacity(0.5), "Clean")
                        legend(Color(.tertiarySystemFill), "No entry")
                    }
                    .font(.caption).foregroundStyle(.secondary)

                    Text("Tap a day to edit it").font(.footnote).foregroundStyle(.secondary)
                }
                .card()
                .padding()
            }
            .appBG(s.accent)
            .navigationTitle("Calendar")
            .sheet(item: $picked) { p in
                DaySheet(date: p.date)
                    .environmentObject(s)
                    .presentationDetents([.height(400)])
            }
        }
    }

    private func cell(_ d: Date) -> some View {
        let c = s.count(d)
        let future = d > Date()
        let fill: Color = c > 0 ? s.accent : (s.answered(d) ? Color.green.opacity(0.5) : Color(.tertiarySystemFill))
        return Button { picked = Pick(date: d) } label: {
            ZStack {
                Circle().fill(fill)
                Text("\(cal.component(.day, from: d))").font(.callout.weight(.medium))
                    .foregroundColor(c > 0 ? .white : .primary)
            }
            .frame(height: 44)
            .overlay(Circle().stroke(cal.isDateInToday(d) ? Color.primary : Color.clear, lineWidth: 1.5))
            .overlay(alignment: .topTrailing) {
                if c > 1 {
                    Text("\(c)").font(.system(size: 10, weight: .bold))
                        .padding(4).background(Color.primary, in: Circle()).foregroundColor(Color(.systemBackground))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(future)
        .opacity(future ? 0.3 : 1)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) { Circle().fill(color).frame(width: 10, height: 10); Text(text) }
    }

    private func shift(_ n: Int) { month = cal.date(byAdding: .month, value: n, to: month)! }
}

struct DaySheet: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) private var dismiss
    let date: Date
    @State private var noteText: String = ""

    var body: some View {
        VStack(spacing: 18) {
            Text(date.formatted(date: .complete, time: .omitted)).font(.headline)
            Stepper(value: Binding(get: { s.count(date) }, set: { s.set(date, $0) }), in: 0...30) {
                Text("Times: \(s.count(date))").font(.title3.monospacedDigit())
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Note").font(.caption).foregroundStyle(.secondary)
                TextField("Optional note for this day", text: $noteText, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .onChange(of: noteText) { s.setNote(date, $0) }
            }
            HStack(spacing: 12) {
                Button("Clear day", role: .destructive) { s.clear(date); dismiss() }
                    .buttonStyle(.bordered)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            Text("0 = marked clean").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBG(s.accent)
        .onAppear { noteText = s.note(date) }
    }
}

// MARK: - Stats
struct StatsTab: View {
    @EnvironmentObject var s: Store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Last 7 days").font(.headline)
                        Chart(s.lastSevenDays, id: \.label) { d in
                            BarMark(x: .value("Day", d.label), y: .value("Count", d.value))
                                .foregroundStyle(s.accent.gradient)
                                .cornerRadius(6)
                        }
                        .frame(height: 180)
                    }
                    .card()

                    HStack(spacing: 12) {
                        tile("\(s.daysTracked)", "Days tracked")
                        tile("\(s.total)", "All-time total")
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Achievements").font(.headline)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(achievements) { a in
                                let unlocked = s.isUnlocked(a)
                                VStack(spacing: 8) {
                                    Image(systemName: a.icon)
                                        .font(.title2)
                                        .foregroundColor(unlocked ? s.accent : .secondary)
                                    Text(a.title).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
                                .opacity(unlocked ? 1 : 0.4)
                            }
                        }
                    }
                    .card()
                }
                .padding()
            }
            .appBG(s.accent)
            .navigationTitle("Stats")
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 16).frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Photos (swipeable "gooning photos" queue)
struct PhotosTab: View {
    @EnvironmentObject var s: Store
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var order: [String] = []
    @State private var index = 0
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            VStack {
                if s.photoFilenames.isEmpty {
                    emptyState
                } else if index >= order.count {
                    doneState
                } else {
                    stack
                    controls
                }
            }
            .padding()
            .appBG(s.accent)
            .navigationTitle("Gooning Photos")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .images) {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .onChange(of: pickerItems) { items in
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                            s.addPhoto(img)
                        }
                    }
                    pickerItems = []
                    resetOrder(keepIndex: true)
                }
            }
            .onAppear { resetOrder(keepIndex: true) }
            .onChange(of: s.photoFilenames) { _ in resetOrder(keepIndex: true) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.stack").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("No photos yet").font(.title3.bold())
            Text("Add photos, then swipe through them one by one.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .images) {
                Text("Add Photos").font(.headline).padding().padding(.horizontal, 20)
                    .background(s.accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundColor(.white)
            }
            Spacer()
        }
    }

    private var doneState: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("🎉").font(.system(size: 64))
            Text("You're done!").font(.largeTitle.bold())
            Text("You've been through all \(order.count) photos.").foregroundStyle(.secondary)
            Button {
                haptic()
                resetOrder(keepIndex: false)
            } label: {
                Text("Start Over").font(.headline).frame(maxWidth: .infinity).padding()
                    .background(s.accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundColor(.white)
            }
            Button(role: .destructive) { confirmDeleteAll = true } label: {
                Text("Delete All Photos")
            }
            Spacer()
        }
        .padding()
        .confirmationDialog("Delete all photos?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { s.deleteAllPhotos(); resetOrder(keepIndex: false) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var stack: some View {
        ZStack {
            ForEach(Array(order.enumerated().reversed()), id: \.offset) { i, filename in
                if i >= index && i < index + 3 {
                    SwipeCard(filename: filename, isTop: i == index) { direction in
                        haptic(.light)
                        withAnimation(.easeOut(duration: 0.25)) { index += 1 }
                    }
                    .environmentObject(s)
                    .zIndex(Double(-i))
                    .scaleEffect(1 - CGFloat(i - index) * 0.04)
                    .offset(y: CGFloat(i - index) * 8)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Text("\(index + 1) of \(order.count)").font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 40) {
                Button { withAnimation { index += 1 } } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 44)).foregroundColor(.secondary)
                }
                Button {
                    if index < order.count { s.deletePhoto(order[index]); resetOrder(keepIndex: true) }
                } label: {
                    Image(systemName: "trash.circle.fill").font(.system(size: 44)).foregroundColor(.red)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func resetOrder(keepIndex: Bool) {
        let newOrder = s.photoFilenames
        if !keepIndex || order != newOrder {
            order = newOrder
            if !keepIndex { index = 0 }
            index = min(index, order.count)
        }
    }
}

struct SwipeCard: View {
    @EnvironmentObject var s: Store
    let filename: String
    let isTop: Bool
    var onSwipe: (Double) -> Void
    @State private var drag: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            Group {
                if let img = s.loadImage(filename) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color(.tertiarySystemFill))
                        .overlay(Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(radius: 8)
            .overlay(alignment: .topLeading) {
                if drag.width < -30 {
                    Text("SKIP").font(.headline.bold()).padding(8).background(.red, in: RoundedRectangle(cornerRadius: 8)).foregroundColor(.white).padding(16).rotationEffect(.degrees(-15))
                }
            }
            .overlay(alignment: .topTrailing) {
                if drag.width > 30 {
                    Text("DONE").font(.headline.bold()).padding(8).background(.green, in: RoundedRectangle(cornerRadius: 8)).foregroundColor(.white).padding(16).rotationEffect(.degrees(15))
                }
            }
            .offset(x: isTop ? drag.width : 0, y: isTop ? drag.height * 0.2 : 0)
            .rotationEffect(.degrees(isTop ? Double(drag.width / 20) : 0))
            .gesture(
                isTop ? DragGesture()
                    .onChanged { drag = $0.translation }
                    .onEnded { value in
                        if abs(value.translation.width) > 110 {
                            let dir: Double = value.translation.width > 0 ? 1 : -1
                            withAnimation(.easeOut(duration: 0.25)) { drag.width = dir * 600 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                onSwipe(dir)
                                drag = .zero
                            }
                        } else {
                            withAnimation(.spring()) { drag = .zero }
                        }
                    } : nil
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 90)
    }
}

// MARK: - Settings
struct SettingsTab: View {
    @EnvironmentObject var s: Store
    @State private var confirmReset = false
    @State private var shareItems: [Any]?

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $s.name)
                }
                Section("Appearance") {
                    Picker("Theme", selection: $s.appearanceRaw) {
                        ForEach(AppearanceMode.allCases) { m in Text(m.label).tag(m.rawValue) }
                    }
                    Picker("Accent color", selection: $s.accentIndex) {
                        ForEach(Array(accentPalette.enumerated()), id: \.offset) { i, item in
                            Text(item.name).tag(i)
                        }
                    }
                }
                Section("Goals") {
                    Stepper("Weekly goal: \(s.weeklyGoal)", value: $s.weeklyGoal, in: 1...50)
                }
                Section("Privacy") {
                    Toggle("Face ID lock", isOn: $s.lockOn)
                    Toggle("Daily check-in reminder (9 PM)", isOn: $s.reminderOn)
                }
                Section("Data") {
                    Button("Export data (CSV)") {
                        shareItems = [s.exportCSV()]
                    }
                    Button("Reset all data", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Settings")
        }
        .alert("Delete everything?", isPresented: $confirmReset) {
            Button("Delete", role: .destructive) { s.resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This wipes all your logged days and can't be undone.")
        }
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            if let items = shareItems { ShareSheet(items: items) }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
