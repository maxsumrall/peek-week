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
    private var contextMenu: NSMenu?

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
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Peek Week")

        let menu = NSMenu()
        let titleItem = NSMenuItem(title: "Peek Week", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = nil
        self.contextMenu = menu

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 290, height: 280)
        popover.contentViewController = NSHostingController(
            rootView: PeekWeekPopover(store: store)
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

        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            popover.performClose(nil)
            statusItem.menu = contextMenu
            button.performClick(nil)
            statusItem.menu = nil
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
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
    let weekNumber: Int
    let quarterLabel: String
    let quarterNumber: Int
    let year: Int
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
            weekNumber: isoWeek.week,
            quarterLabel: quarterLabel,
            quarterNumber: quarter,
            year: year,
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
            return "done"
        case (0, let d):
            return "\(d)d left"
        case (let w, 0):
            return "\(w)w left"
        case (let w, let d):
            return "\(w)w \(d)d left"
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

    var percentComplete: Int {
        Int((fractionComplete * 100).rounded())
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
    private static let didEnableLoginItemKey = "PeekWeek.didEnableLoginItemRegistration"
    private static let legacyDidAttemptRegistrationKey = "PeekWeek.didAttemptLoginItemRegistration"

    static func enableOnFirstRunIfPossible() {
        guard #available(macOS 13.0, *) else {
            return
        }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didEnableLoginItemKey) else {
            return
        }

        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }

            defaults.set(true, forKey: didEnableLoginItemKey)
            defaults.removeObject(forKey: legacyDidAttemptRegistrationKey)
        } catch {
            defaults.removeObject(forKey: didEnableLoginItemKey)
            NSLog("Peek Week could not enable launch at login automatically: \(error.localizedDescription)")
        }
    }
}

struct PeekWeekPopover: View {
    @ObservedObject var store: WeekStore

    var body: some View {
        let metrics = store.metrics

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(metrics.weekNumber)")
                        .font(.system(size: 44, weight: .heavy))
                        .tracking(-2)
                        .lineLimit(1)
                    HStack(alignment: .center, spacing: 6) {
                        Text("Q" + String(metrics.quarterNumber))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(LinearGradient(
                                        colors: [Color(red: 0.03, green: 0.57, blue: 0.70), Color(red: 0.05, green: 0.46, blue: 0.56)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                            )
                        Text(String(metrics.year))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 80, alignment: .leading)

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 2)
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 14) {
                    CountdownStat(
                        title: "Quarter",
                        summary: metrics.quarterRemaining.summary
                    )
                    CountdownStat(
                        title: "Year",
                        summary: metrics.yearRemaining.summary
                    )
                }
                .padding(.leading, 16)
            }

            InsetStatCard(
                title: "Quarter",
                subtitle: metrics.quarterProgress.subtitle,
                percent: metrics.quarterProgress.percentComplete,
                fraction: metrics.quarterProgress.fractionComplete,
                gradient: [Color(red: 0.13, green: 0.83, blue: 0.93), Color(red: 0.03, green: 0.57, blue: 0.70)]
            )

            InsetStatCard(
                title: "Year",
                subtitle: metrics.yearProgress.subtitle,
                percent: metrics.yearProgress.percentComplete,
                fraction: metrics.yearProgress.fractionComplete,
                gradient: [Color(red: 0.99, green: 0.83, blue: 0.29), Color(red: 0.85, green: 0.47, blue: 0.02)]
            )

        }
        .padding(22)
        .frame(width: 290)
    }
}

struct CountdownStat: View {
    let title: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(styledSummary)
                .tracking(-0.2)
        }
    }

    private var styledSummary: AttributedString {
        var full = AttributedString(summary)
        full.font = .system(size: 15, weight: .semibold)
        if let range = full.range(of: " left") {
            full[range].font = .system(size: 11, weight: .regular)
            full[range].foregroundColor = .secondary
        }
        return full
    }
}

struct InsetStatCard: View {
    let title: String
    let subtitle: String
    let percent: Int
    let fraction: Double
    let gradient: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))

                    Capsule()
                        .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(36, geometry.size.width * fraction))
                        .overlay(alignment: .trailing) {
                            Text("\(percent)%")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.trailing, 7)
                        }
                }
            }
            .frame(height: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
