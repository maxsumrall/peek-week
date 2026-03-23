import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
struct PeekWeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
                .frame(width: 1, height: 1)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = WeekStore()
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusController = StatusItemController(store: store)
        statusController.install()
        self.statusController = statusController

        store.start()
        LaunchAtLoginController.enableOnFirstRunIfPossible()
    }
}

final class StatusItemController: NSObject {
    private let store: WeekStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?

    init(store: WeekStore) {
        self.store = store
        super.init()
    }

    func install() {
        guard let button = statusItem.button else {
            assertionFailure("Missing status item button")
            return
        }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        button.setAccessibilityLabel("Peek Week")

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 300, height: 250)
        popover.contentViewController = NSHostingController(
            rootView: PeekWeekPopover(store: store) {
                NSApp.terminate(nil)
            }
        )

        cancellable = store.$metrics
            .receive(on: RunLoop.main)
            .sink { [weak self] metrics in
                self?.applyTitle(metrics.menuBarTitle)
            }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func applyTitle(_ title: String) {
        guard let button = statusItem.button else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        button.attributedTitle = NSAttributedString(string: title, attributes: attributes)
    }
}

final class WeekStore: ObservableObject {
    @Published private(set) var metrics: WeekMetrics = .now()

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    deinit {
        stop()
    }

    func start() {
        refresh()
        installObservers()
        installTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    func refresh(now: Date = Date()) {
        metrics = .now(referenceDate: now)
    }

    private func installObservers() {
        guard observers.isEmpty else {
            return
        }

        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: NSNotification.Name.NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        })

        observers.append(center.addObserver(
            forName: NSNotification.Name.NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        })

        observers.append(center.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        })
    }

    private func installTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
}

struct WeekMetrics: Equatable {
    let menuBarTitle: String
    let isoWeekLabel: String
    let quarterLabel: String
    let quarterRemainingIncludingCurrent: Int
    let quarterRemainingExcludingCurrent: Int
    let yearRemainingIncludingCurrent: Int
    let yearRemainingExcludingCurrent: Int
    let quarterProgress: ProgressSnapshot
    let yearProgress: ProgressSnapshot

    static func now(referenceDate: Date = Date()) -> WeekMetrics {
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = .current

        var gregorianCalendar = Calendar(identifier: .gregorian)
        gregorianCalendar.timeZone = .current

        let isoWeek = ISOWeek(date: referenceDate, calendar: isoCalendar)
        let weekLabel = "W\(isoWeek.week)"

        let quarter = gregorianCalendar.component(.quarter, from: referenceDate)
        let year = gregorianCalendar.component(.year, from: referenceDate)
        let quarterLabel = "Q\(quarter) \(year)"

        let currentWeekStart = isoWeek.startDate
        let quarterInterval = gregorianCalendar.dateInterval(of: .quarter, for: referenceDate)!
        let yearInterval = gregorianCalendar.dateInterval(of: .year, for: referenceDate)!

        let quarterWeeks = ISOWeek.weeksIntersecting(interval: quarterInterval, calendar: isoCalendar)
        let yearWeeks = ISOWeek.weeksIntersecting(interval: yearInterval, calendar: isoCalendar)

        let quarterRemainingIncludingCurrent = quarterWeeks.filter { $0.startDate >= currentWeekStart }.count
        let yearRemainingIncludingCurrent = yearWeeks.filter { $0.startDate >= currentWeekStart }.count

        let quarterElapsedIncludingCurrent = quarterWeeks.filter { $0.startDate <= currentWeekStart }.count
        let yearElapsedIncludingCurrent = yearWeeks.filter { $0.startDate <= currentWeekStart }.count

        return WeekMetrics(
            menuBarTitle: weekLabel,
            isoWeekLabel: weekLabel,
            quarterLabel: quarterLabel,
            quarterRemainingIncludingCurrent: quarterRemainingIncludingCurrent,
            quarterRemainingExcludingCurrent: max(0, quarterRemainingIncludingCurrent - 1),
            yearRemainingIncludingCurrent: yearRemainingIncludingCurrent,
            yearRemainingExcludingCurrent: max(0, yearRemainingIncludingCurrent - 1),
            quarterProgress: ProgressSnapshot(
                elapsedWeeksIncludingCurrent: quarterElapsedIncludingCurrent,
                totalWeeks: quarterWeeks.count
            ),
            yearProgress: ProgressSnapshot(
                elapsedWeeksIncludingCurrent: yearElapsedIncludingCurrent,
                totalWeeks: yearWeeks.count
            )
        )
    }
}

struct ProgressSnapshot: Equatable {
    let elapsedWeeksIncludingCurrent: Int
    let totalWeeks: Int

    var fractionComplete: Double {
        guard totalWeeks > 0 else {
            return 0
        }
        return min(max(Double(elapsedWeeksIncludingCurrent) / Double(totalWeeks), 0), 1)
    }

    var subtitle: String {
        "\(elapsedWeeksIncludingCurrent) / \(totalWeeks) weeks"
    }
}

struct ISOWeek: Hashable {
    let yearForWeekOfYear: Int
    let week: Int
    let startDate: Date

    init(date: Date, calendar: Calendar) {
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)!
        startDate = interval.start
        yearForWeekOfYear = calendar.component(.yearForWeekOfYear, from: date)
        week = calendar.component(.weekOfYear, from: date)
    }

    static func weeksIntersecting(interval: DateInterval, calendar: Calendar) -> [ISOWeek] {
        guard let firstWeek = calendar.dateInterval(of: .weekOfYear, for: interval.start) else {
            return []
        }

        var weeks: [ISOWeek] = []
        var seen: Set<ISOWeek> = []
        var cursor = firstWeek.start

        while cursor < interval.end {
            let week = ISOWeek(date: cursor, calendar: calendar)
            if !seen.contains(week) {
                let weekInterval = calendar.dateInterval(of: .weekOfYear, for: cursor)!
                if weekInterval.end > interval.start && weekInterval.start < interval.end {
                    weeks.append(week)
                    seen.insert(week)
                }
            }

            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else {
                break
            }
            cursor = next
        }

        return weeks.sorted { $0.startDate < $1.startDate }
    }
}

enum LaunchAtLoginController {
    private static let didAttemptRegistrationKey = "PeekWeek.didAttemptLoginItemRegistration"

    static func enableOnFirstRunIfPossible() {
        guard #available(macOS 13.0, *) else {
            return
        }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didAttemptRegistrationKey) else {
            return
        }

        defaults.set(true, forKey: didAttemptRegistrationKey)

        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("Peek Week could not enable launch at login automatically: \(error.localizedDescription)")
        }
    }
}

struct PeekWeekPopover: View {
    @ObservedObject var store: WeekStore
    let quit: () -> Void

    var body: some View {
        let metrics = store.metrics

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(metrics.isoWeekLabel)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Peek Week")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(metrics.quarterLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            StatLine(
                title: "Quarter",
                includingCurrent: metrics.quarterRemainingIncludingCurrent,
                excludingCurrent: metrics.quarterRemainingExcludingCurrent
            )

            ProgressStrip(
                title: "Quarter progress",
                tint: Color(red: 0.07, green: 0.57, blue: 0.73),
                snapshot: metrics.quarterProgress
            )

            StatLine(
                title: "Year",
                includingCurrent: metrics.yearRemainingIncludingCurrent,
                excludingCurrent: metrics.yearRemainingExcludingCurrent
            )

            ProgressStrip(
                title: "Year progress",
                tint: Color(red: 0.84, green: 0.47, blue: 0.04),
                snapshot: metrics.yearProgress
            )

            HStack {
                Spacer()
                Button("Quit", action: quit)
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct StatLine: View {
    let title: String
    let includingCurrent: Int
    let excludingCurrent: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text("\(includingCurrent) incl / \(excludingCurrent) excl remaining")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

struct ProgressStrip: View {
    let title: String
    let tint: Color
    let snapshot: ProgressSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(snapshot.subtitle)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(10, geometry.size.width * snapshot.fractionComplete))
                }
            }
            .frame(height: 8)
        }
    }
}
