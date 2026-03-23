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
        popover.contentSize = NSSize(width: 320, height: 270)
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
    let quarterRemaining: RemainingTimeSnapshot
    let yearRemaining: RemainingTimeSnapshot
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

        let quarterInterval = gregorianCalendar.dateInterval(of: .quarter, for: referenceDate)!
        let yearInterval = gregorianCalendar.dateInterval(of: .year, for: referenceDate)!

        return WeekMetrics(
            menuBarTitle: weekLabel,
            isoWeekLabel: weekLabel,
            quarterLabel: quarterLabel,
            quarterRemaining: RemainingTimeSnapshot(referenceDate: referenceDate, intervalEnd: quarterInterval.end, calendar: gregorianCalendar),
            yearRemaining: RemainingTimeSnapshot(referenceDate: referenceDate, intervalEnd: yearInterval.end, calendar: gregorianCalendar),
            quarterProgress: ProgressSnapshot(referenceDate: referenceDate, interval: quarterInterval, calendar: gregorianCalendar),
            yearProgress: ProgressSnapshot(referenceDate: referenceDate, interval: yearInterval, calendar: gregorianCalendar)
        )
    }
}

struct RemainingTimeSnapshot: Equatable {
    let totalDaysRemaining: Int
    let weeks: Int
    let days: Int

    init(referenceDate: Date, intervalEnd: Date, calendar: Calendar) {
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let remainingDays = max(0, calendar.dateComponents([.day], from: startOfToday, to: intervalEnd).day ?? 0)

        totalDaysRemaining = remainingDays
        weeks = remainingDays / 7
        days = remainingDays % 7
    }

    var summary: String {
        switch (weeks, days) {
        case (0, 0):
            return "today"
        case (0, let days):
            return "\(days)d left"
        case (let weeks, 0):
            return "\(weeks)w left"
        case (let weeks, let days):
            return "\(weeks)w \(days)d left"
        }
    }
}

struct ProgressSnapshot: Equatable {
    let elapsedDays: Int
    let totalDays: Int

    init(referenceDate: Date, interval: DateInterval, calendar: Calendar) {
        let startOfInterval = calendar.startOfDay(for: interval.start)
        let startOfToday = calendar.startOfDay(for: referenceDate)
        totalDays = max(1, calendar.dateComponents([.day], from: startOfInterval, to: interval.end).day ?? 1)
        elapsedDays = min(max(0, calendar.dateComponents([.day], from: startOfInterval, to: startOfToday).day ?? 0), totalDays)
    }

    var fractionComplete: Double {
        min(max(Double(elapsedDays) / Double(totalDays), 0), 1)
    }

    var subtitle: String {
        "\(elapsedDays) / \(totalDays) days"
    }
}

struct ISOWeek: Hashable {
    let yearForWeekOfYear: Int
    let week: Int

    init(date: Date, calendar: Calendar) {
        yearForWeekOfYear = calendar.component(.yearForWeekOfYear, from: date)
        week = calendar.component(.weekOfYear, from: date)
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
                title: "Quarter left",
                summary: metrics.quarterRemaining.summary,
                detail: "Calendar time remaining in \(metrics.quarterLabel)"
            )

            ProgressStrip(
                title: "Quarter progress",
                tint: Color(red: 0.07, green: 0.57, blue: 0.73),
                snapshot: metrics.quarterProgress
            )

            StatLine(
                title: "Year left",
                summary: metrics.yearRemaining.summary,
                detail: "Calendar time remaining this year"
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
        .frame(width: 320)
    }
}

struct StatLine: View {
    let title: String
    let summary: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(summary)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.system(size: 11, weight: .medium))
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
