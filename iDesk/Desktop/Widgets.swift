import SwiftUI
import EventKit
import CoreLocation

/// Desktop widgets: clock, month, weather, upcoming events, reminders, a Pomodoro timer. Each can be shown or hidden
/// (desktop menu → Widgets) and dragged anywhere on the desktop; places are kept.
enum WidgetKind: String, CaseIterable, Codable {
    case clock, calendar, weather, events, reminders, pomodoro

    var title: String.LocalizationValue {
        switch self {
        case .clock: return "Clock"
        case .calendar: return "Month"
        case .weather: return "Weather"
        case .events: return "Upcoming events"
        case .reminders: return "Reminders"
        case .pomodoro: return "Focus timer"
        }
    }
    var symbol: String {
        switch self {
        case .clock: return "clock"
        case .calendar: return "calendar"
        case .weather: return "cloud.sun"
        case .events: return "calendar.badge.clock"
        case .reminders: return "checklist"
        case .pomodoro: return "timer"
        }
    }
    static let width: CGFloat = 236
    var height: CGFloat {
        switch self {
        case .clock: return 86
        case .calendar: return 212
        case .weather: return 112
        case .events: return 156
        case .reminders: return 156
        case .pomodoro: return 124
        }
    }
}

final class WidgetStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WidgetStore()

    @Published private(set) var enabled: [WidgetKind] = []
    /// Places the user dragged widgets to (top-left corner); others follow each other in the top-right column.
    @Published var positions: [WidgetKind: CGPoint] = [:]

    // Weather
    struct Weather { var place: String; var temp: Double; var code: Int; var high: Double; var low: Double }
    @Published private(set) var weather: Weather?
    @Published private(set) var weatherNote: String?
    private let location = CLLocationManager()
    private var lastWeather: Date?

    // Calendar and reminders
    private let store = EKEventStore()
    struct Event { let title: String; let start: Date; let allDay: Bool; let color: CGColor? }
    @Published private(set) var events: [Event] = []
    @Published private(set) var reminders: [String] = []
    @Published private(set) var calendarNote: String?
    @Published private(set) var remindersNote: String?

    // Focus timer
    enum Phase: String { case focus, rest }
    @Published private(set) var phase: Phase = .focus
    @Published private(set) var endsAt: Date?
    @Published private(set) var remaining: TimeInterval = 25 * 60
    static let focusLength: TimeInterval = 25 * 60, restLength: TimeInterval = 5 * 60
    private var phaseTimer: Timer?

    private static let enabledKey = "iDesk.widgets", positionsKey = "iDesk.widgetPositions"

    override init() {
        super.init()
        if let names = UserDefaults.standard.stringArray(forKey: Self.enabledKey) {
            enabled = names.compactMap(WidgetKind.init(rawValue:))
        } else {
            enabled = [.clock, .calendar]
        }
        if let data = UserDefaults.standard.data(forKey: Self.positionsKey),
           let saved = try? JSONDecoder().decode([String: [Double]].self, from: data) {
            for (k, v) in saved { if let kind = WidgetKind(rawValue: k), v.count == 2 { positions[kind] = CGPoint(x: v[0], y: v[1]) } }
        }
        location.delegate = self
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.loadCalendar()
        }
        refresh()
        Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func isOn(_ k: WidgetKind) -> Bool { enabled.contains(k) }

    func toggle(_ k: WidgetKind) {
        if isOn(k) { enabled.removeAll { $0 == k } } else { enabled.append(k) }
        UserDefaults.standard.set(enabled.map(\.rawValue), forKey: Self.enabledKey)
        refresh()
    }

    func savePositions() {
        let dict = Dictionary(uniqueKeysWithValues: positions.map { ($0.key.rawValue, [Double($0.value.x), Double($0.value.y)]) })
        if let data = try? JSONEncoder().encode(dict) { UserDefaults.standard.set(data, forKey: Self.positionsKey) }
    }

    func resetPositions() {
        positions = [:]
        savePositions()
    }

    /// Reloads what the shown widgets need (asks for permission the first time a widget needs it).
    func refresh() {
        if isOn(.weather) { loadWeather() }
        if isOn(.events) || isOn(.reminders) { loadCalendar() }
    }

    // MARK: Weather (Open-Meteo: free, no account)

    private func loadWeather() {
        if let last = lastWeather, Date().timeIntervalSince(last) < 20 * 60, weather != nil { return }
        switch location.authorizationStatus {
        case .notDetermined: location.requestWhenInUseAuthorization()
        case .denied, .restricted: weatherNote = String(localized: "Allow Location for APLite in the iPhone's Settings to see the weather.")
        default: location.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if isOn(.weather), manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied {
            weatherNote = String(localized: "Allow Location for APLite in the iPhone's Settings to see the weather.")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { if self.weather == nil { self.weatherNote = String(localized: "Location unavailable.") } }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let lat = String(format: "%.3f", loc.coordinate.latitude), lon = String(format: "%.3f", loc.coordinate.longitude)
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
                             + "&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1")
        else { return }
        var place = ""
        let group = DispatchGroup()
        group.enter()
        CLGeocoder().reverseGeocodeLocation(loc) { marks, _ in
            place = marks?.first?.locality ?? marks?.first?.administrativeArea ?? ""
            group.leave()
        }
        group.enter()
        var parsed: (Double, Int, Double, Double)?
        URLSession.shared.dataTask(with: url) { data, _, _ in
            defer { group.leave() }
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any], let daily = json["daily"] as? [String: Any],
                  let t = current["temperature_2m"] as? Double, let code = current["weather_code"] as? Int,
                  let hi = (daily["temperature_2m_max"] as? [Double])?.first, let lo = (daily["temperature_2m_min"] as? [Double])?.first
            else { return }
            parsed = (t, code, hi, lo)
        }.resume()
        group.notify(queue: .main) {
            guard let p = parsed else { if self.weather == nil { self.weatherNote = String(localized: "Weather unavailable.") }; return }
            self.weather = Weather(place: place, temp: p.0, code: p.1, high: p.2, low: p.3)
            self.weatherNote = nil
            self.lastWeather = Date()
        }
    }

    static func weatherSymbol(_ code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    // MARK: Calendar and reminders (on the iPhone)

    private func loadCalendar() {
        if isOn(.events) {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .notDetermined:
                store.requestFullAccessToEvents { [weak self] _, _ in DispatchQueue.main.async { self?.loadCalendar() } }
            case .fullAccess, .authorized:
                let now = Date(), end = Calendar.current.date(byAdding: .day, value: 7, to: now)!
                let found = store.events(matching: store.predicateForEvents(withStart: now, end: end, calendars: nil))
                    .sorted { $0.startDate < $1.startDate }.prefix(4)
                events = found.map { Event(title: $0.title ?? "", start: $0.startDate, allDay: $0.isAllDay, color: $0.calendar.cgColor) }
                calendarNote = nil
            default:
                calendarNote = String(localized: "Allow Calendars for APLite in the iPhone's Settings.")
            }
        }
        if isOn(.reminders) {
            switch EKEventStore.authorizationStatus(for: .reminder) {
            case .notDetermined:
                store.requestFullAccessToReminders { [weak self] _, _ in DispatchQueue.main.async { self?.loadCalendar() } }
            case .fullAccess, .authorized:
                store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) { list in
                    let titles = (list ?? []).sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
                        .prefix(5).compactMap(\.title)
                    DispatchQueue.main.async { self.reminders = titles; self.remindersNote = nil }
                }
            default:
                remindersNote = String(localized: "Allow Reminders for APLite in the iPhone's Settings.")
            }
        }
    }

    // MARK: Focus timer

    var isRunning: Bool { endsAt != nil }

    func startPause() {
        if let end = endsAt {
            remaining = max(0, end.timeIntervalSinceNow)
            endsAt = nil
            phaseTimer?.invalidate()
        } else {
            endsAt = Date().addingTimeInterval(remaining)
            schedulePhaseEnd()
        }
    }

    func reset() {
        phaseTimer?.invalidate()
        endsAt = nil
        phase = .focus
        remaining = Self.focusLength
    }

    private func schedulePhaseEnd() {
        phaseTimer?.invalidate()
        guard let end = endsAt else { return }
        phaseTimer = Timer.scheduledTimer(withTimeInterval: max(0.1, end.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            self?.phaseEnded()
        }
    }

    private func phaseEnded() {
        let model = DesktopModel.shared
        if phase == .focus {
            phase = .rest
            remaining = Self.restLength
            model.showToast(String(localized: "Focus time is over: take a 5-minute break."))
        } else {
            phase = .focus
            remaining = Self.focusLength
            model.showToast(String(localized: "Break is over: ready for the next 25 minutes."))
        }
        endsAt = Date().addingTimeInterval(remaining)
        schedulePhaseEnd()
    }

    func timeLeft(at now: Date) -> TimeInterval { endsAt.map { max(0, $0.timeIntervalSince(now)) } ?? remaining }
}

// MARK: - Layout and input

extension DesktopModel {
    /// Where a widget is: where it was dragged, else in a column at the top right.
    func widgetRect(_ k: WidgetKind) -> CGRect {
        let store = WidgetStore.shared
        let size = CGSize(width: WidgetKind.width, height: k.height)
        if let p = store.positions[k] {
            let x = min(max(0, p.x), screenSize.width - size.width), y = min(max(0, p.y), desktopArea.maxY - size.height)
            return CGRect(origin: CGPoint(x: x, y: y), size: size)
        }
        var y: CGFloat = 24
        for other in store.enabled where store.positions[other] == nil {
            if other == k { break }
            y += other.height + 12
        }
        return CGRect(x: screenSize.width - size.width - 24, y: y, width: size.width, height: size.height)
    }

    /// The shown widget under the pointer (widgets lie on the desktop, under the windows).
    func widget(at p: CGPoint) -> WidgetKind? {
        guard showWidgets, topWindow(at: p) == nil else { return nil }
        return WidgetStore.shared.enabled.reversed().first { widgetRect($0).contains(p) }
    }

    func pomodoroButtonRect(_ i: Int) -> CGRect {
        let r = widgetRect(.pomodoro)
        return CGRect(x: r.minX + 16 + CGFloat(i) * 76, y: r.maxY - 42, width: 68, height: 28)
    }

    /// A click on a widget: the timer's buttons; the others open what they show.
    func clickWidget(_ k: WidgetKind, at p: CGPoint) {
        let store = WidgetStore.shared
        switch k {
        case .pomodoro:
            if pomodoroButtonRect(0).contains(p) { store.startPause() }
            else if pomodoroButtonRect(1).contains(p) { store.reset() }
        case .weather:
            store.refresh()
        default:
            break
        }
    }

    func widgetsMenu() -> [MenuItem] {
        let store = WidgetStore.shared
        var items: [MenuItem] = WidgetKind.allCases.map { k in
            MenuItem(k.title, store.isOn(k) ? "checkmark.circle.fill" : k.symbol) { [weak self] in
                store.toggle(k)
                if store.isOn(k) { self?.showWidgets = true }
                self?.objectWillChange.send()
            }
        }
        items += [.separator, MenuItem("Put widgets back in place", "arrow.uturn.backward") { [weak self] in
            store.resetPositions(); self?.objectWillChange.send()
        }]
        return items
    }
}

// MARK: - Views

struct DesktopWidgetsView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var store = WidgetStore.shared
    @ObservedObject var cursor: CursorModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            ZStack(alignment: .topLeading) {
                ForEach(store.enabled, id: \.self) { k in
                    let r = model.widgetRect(k)
                    content(k, ctx.date)
                        .padding(14)
                        .frame(width: r.width, height: r.height, alignment: .topLeading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .offset(x: r.minX, y: r.minY)
                }
            }
        }
    }

    @ViewBuilder private func content(_ k: WidgetKind, _ date: Date) -> some View {
        switch k {
        case .clock: clock(date)
        case .calendar: month(date)
        case .weather: weather
        case .events: events
        case .reminders: reminders
        case .pomodoro: pomodoro(date)
        }
    }

    private func header(_ k: WidgetKind) -> some View {
        Label { Text(String(localized: k.title)).font(.system(size: 12, weight: .semibold)) } icon: { Image(systemName: k.symbol) }
            .foregroundStyle(.white.opacity(0.7))
    }

    private func note(_ s: String) -> some View {
        Text(verbatim: s).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
    }

    private func clock(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.75))
        }
    }

    private func month(_ date: Date) -> some View {
        let cal = Calendar.current
        let month = cal.dateInterval(of: .month, for: date)!
        let days = cal.range(of: .day, in: .month, for: date)!.count
        let lead = (cal.component(.weekday, from: month.start) - cal.firstWeekday + 7) % 7
        let today = cal.component(.day, from: date)
        let symbols = (0..<7).map { cal.veryShortStandaloneWeekdaySymbols[($0 + cal.firstWeekday - 1) % 7] }
        let cells: [Int?] = Array(repeating: nil, count: lead) + (1...days).map { $0 }
        return VStack(alignment: .leading, spacing: 6) {
            Text(date.formatted(.dateTime.month(.wide).year())).font(.system(size: 14, weight: .semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 3), count: 7), spacing: 3) {
                ForEach(symbols.indices, id: \.self) { i in
                    Text(symbols[i]).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                }
                ForEach(cells.indices, id: \.self) { i in
                    if let d = cells[i] {
                        Text(verbatim: "\(d)")
                            .font(.system(size: 11, weight: d == today ? .bold : .regular).monospacedDigit())
                            .frame(width: 24, height: 21)
                            .background(Circle().fill(d == today ? Color.accentColor : .clear))
                    } else {
                        Color.clear.frame(width: 24, height: 21)
                    }
                }
            }
        }
    }

    private var weather: some View {
        VStack(alignment: .leading, spacing: 6) {
            header(.weather)
            if let w = store.weather {
                HStack(spacing: 12) {
                    Image(systemName: WidgetStore.weatherSymbol(w.code)).symbolRenderingMode(.multicolor).font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(Int(w.temp.rounded()))°").font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text(verbatim: "\(w.place)  ↑\(Int(w.high.rounded()))° ↓\(Int(w.low.rounded()))°")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                }
            } else {
                note(store.weatherNote ?? String(localized: "Loading…"))
            }
        }
    }

    private var events: some View {
        VStack(alignment: .leading, spacing: 6) {
            header(.events)
            if let n = store.calendarNote { note(n) }
            else if store.events.isEmpty { note(String(localized: "Nothing in the next 7 days.")) }
            ForEach(Array(store.events.enumerated()), id: \.offset) { _, e in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(e.color.map { Color(cgColor: $0) } ?? .accentColor).frame(width: 3, height: 24)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: e.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(verbatim: e.allDay ? e.start.formatted(.dateTime.weekday().day().month())
                                                : e.start.formatted(.dateTime.weekday().hour().minute()))
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: 6) {
            header(.reminders)
            if let n = store.remindersNote { note(n) }
            else if store.reminders.isEmpty { note(String(localized: "All done.")) }
            ForEach(Array(store.reminders.enumerated()), id: \.offset) { _, title in
                HStack(spacing: 8) {
                    Image(systemName: "circle").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    Text(verbatim: title).font(.system(size: 12)).lineLimit(1)
                }
            }
        }
    }

    private func pomodoro(_ date: Date) -> some View {
        let left = Int(store.timeLeft(at: date).rounded(.up))
        return VStack(alignment: .leading, spacing: 4) {
            header(.pomodoro)
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%02d:%02d", left / 60, left % 60))
                    .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                Text(store.phase == .focus ? "Focus" : "Break")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(store.phase == .focus ? Color.orange : Color.green)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                button(store.isRunning ? "Pause" : "Start", 0, primary: true)
                button("Reset", 1, primary: false)
            }
        }
    }

    private func button(_ title: LocalizedStringKey, _ i: Int, primary: Bool) -> some View {
        let hovered = model.pomodoroButtonRect(i).contains(cursor.position)
        return Text(title).font(.system(size: 12, weight: .semibold))
            .frame(width: 68, height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(primary ? Color.accentColor.opacity(hovered ? 1 : 0.8)
                                                                       : Color.white.opacity(hovered ? 0.22 : 0.12)))
    }
}
