import SwiftUI
import LocalAuthentication
import UserNotifications

// MARK: - App
@main
struct GoonTrackerApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.58, green: 0.42, blue: 1.0)
    static let good = Color(red: 0.25, green: 0.8, blue: 0.5)
}

extension View {
    func card() -> some View {
        padding(20).frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    func appBG() -> some View {
        background(
            LinearGradient(colors: [Color(red: 0.08, green: 0.06, blue: 0.16), Color(red: 0.03, green: 0.03, blue: 0.07)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        )
    }
}

func haptic() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }

// MARK: - Store
final class Store: ObservableObject {
    private let d = UserDefaults.standard
    private let cal = Calendar.current

    @Published var name: String { didSet { d.set(name, forKey: "name") } }
    @Published var entries: [String: Int] { didSet { d.set(entries, forKey: "entries") } }
    @Published var lockOn: Bool { didSet { d.set(lockOn, forKey: "lockOn") } }
    @Published var reminderOn: Bool { didSet { d.set(reminderOn, forKey: "reminderOn"); updateReminder() } }
    let startDate: Date

    init() {
        name = d.string(forKey: "name") ?? ""
        entries = d.dictionary(forKey: "entries") as? [String: Int] ?? [:]
        lockOn = d.bool(forKey: "lockOn")
        reminderOn = d.bool(forKey: "reminderOn")
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
    func clear(_ date: Date) { entries[Store.key(date)] = nil }

    var total: Int { entries.values.reduce(0, +) }

    var thisMonth: Int {
        let p = String(Store.key(Date()).prefix(7))
        return entries.filter { $0.key.hasPrefix(p) }.values.reduce(0, +)
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

    func resetAll() {
        entries = [:]
        d.set(Calendar.current.startOfDay(for: Date()), forKey: "start")
    }

    // Daily reminder at 9pm (deliberately discreet wording)
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
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock the app") { ok, _ in
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
            Text("👋").font(.system(size: 64))
            Text("What's your name?").font(.largeTitle.bold())
            TextField("Name", text: $text)
                .textInputAutocapitalization(.words)
                .multilineTextAlignment(.center)
                .font(.title3)
                .padding()
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .submitLabel(.done)
            Button {
                haptic()
                store.name = text.trimmingCharacters(in: .whitespaces)
            } label: {
                Text("Continue").font(.headline).frame(maxWidth: .infinity).padding()
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundColor(.white)
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(text.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            Spacer()
        }
        .padding(28)
        .appBG()
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
        .appBG()
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
            SettingsTab().tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

// MARK: - Home
struct Home: View {
    @EnvironmentObject var s: Store

    private var status: String {
        let t = Date()
        guard s.answered(t) else { return "Not logged yet today" }
        let c = s.count(t)
        return c == 0 ? "Clean today ✅" : "Logged \(c)× today"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hey, \(s.name) 👋").font(.title2.bold())
                        Text(Date(), style: .date).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                VStack(spacing: 16) {
                    Text("Have you gooned today?")
                        .font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        answerButton("Yes", color: Theme.accent) {
                            s.set(Date(), s.count(Date()) + 1)
                        }
                        answerButton("No", color: Theme.good) {
                            s.set(Date(), 0)
                        }
                    }
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
                .card()

                VStack(spacing: 4) {
                    Text("\(s.total)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                    Text("times total").foregroundStyle(.secondary)
                }
                .card()

                HStack(spacing: 12) {
                    tile("\(s.daysClean)", "Days clean")
                    tile("\(s.bestStreak)", "Best streak")
                    tile("\(s.thisMonth)", "This month")
                }
            }
            .padding()
        }
        .appBG()
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
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                    legend(Theme.accent, "Gooned")
                    legend(Theme.good.opacity(0.5), "Clean")
                    legend(Color.white.opacity(0.1), "No entry")
                }
                .font(.caption).foregroundStyle(.secondary)

                Text("Tap a day to edit it").font(.footnote).foregroundStyle(.secondary)
            }
            .card()
            .padding()
        }
        .appBG()
        .sheet(item: $picked) { p in
            DaySheet(date: p.date)
                .environmentObject(s)
                .presentationDetents([.height(320)])
        }
    }

    private func cell(_ d: Date) -> some View {
        let c = s.count(d)
        let future = d > Date()
        let fill: Color = c > 0 ? Theme.accent : (s.answered(d) ? Theme.good.opacity(0.5) : Color.white.opacity(0.08))
        return Button { picked = Pick(date: d) } label: {
            ZStack {
                Circle().fill(fill)
                Text("\(cal.component(.day, from: d))").font(.callout.weight(.medium))
            }
            .frame(height: 44)
            .overlay(Circle().stroke(cal.isDateInToday(d) ? Color.white : Color.clear, lineWidth: 1.5))
            .overlay(alignment: .topTrailing) {
                if c > 1 {
                    Text("\(c)").font(.system(size: 10, weight: .bold))
                        .padding(4).background(Color.white, in: Circle()).foregroundColor(.black)
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

    var body: some View {
        VStack(spacing: 20) {
            Text(date.formatted(date: .complete, time: .omitted)).font(.headline)
            Stepper(value: Binding(get: { s.count(date) }, set: { s.set(date, $0) }), in: 0...30) {
                Text("Times: \(s.count(date))").font(.title3.monospacedDigit())
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
        .appBG()
    }
}

// MARK: - Settings
struct SettingsTab: View {
    @EnvironmentObject var s: Store
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name", text: $s.name)
            }
            Section("Privacy") {
                Toggle("Face ID lock", isOn: $s.lockOn)
                Toggle("Daily check-in reminder (9 PM)", isOn: $s.reminderOn)
            }
            Section {
                Button("Reset all data", role: .destructive) { confirmReset = true }
            }
        }
        .scrollContentBackground(.hidden)
        .appBG()
        .alert("Delete everything?", isPresented: $confirmReset) {
            Button("Delete", role: .destructive) { s.resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This wipes all your logged days and can't be undone.")
        }
    }
}
