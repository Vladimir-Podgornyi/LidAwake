import AppKit
import LidAwakeCore
import SwiftUI

/// Owns the one activity log window: it is made on first use and kept, so the row brings the
/// same window to the front every time.
@MainActor
final class ActivityLogWindowController {
    nonisolated static let width: CGFloat = 440
    nonisolated static let initialHeight: CGFloat = 560
    nonisolated static let minimumHeight: CGFloat = 240

    private let log: ActivityLog
    private let accent: AccentPreference
    private var window: NSWindow?

    init(log: ActivityLog, accent: AccentPreference) {
        self.log = log
        self.accent = accent
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        // The app has no Dock icon and stays without one; activating it only brings its window
        // in front of the other apps.
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = ActivityLogNSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.initialHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Activity Log")
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: Self.width, height: Self.minimumHeight)
        window.contentMaxSize = NSSize(width: Self.width, height: .greatestFiniteMagnitude)
        let host = NSHostingView(rootView: ActivityLogScreen(log: log, accent: accent))
        // The window sets the size; the content only fills it.
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(NSSize(width: Self.width, height: Self.initialHeight))
        window.center()
        return window
    }
}

/// An app without a main menu gets no Close item, so the window answers ⌘W itself.
private final class ActivityLogNSWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Follows the log, so a new entry shows up in the open window; the minute timeline moves the
/// Today and Yesterday headings past midnight.
struct ActivityLogScreen: View {
    @ObservedObject var log: ActivityLog
    @ObservedObject var accent: AccentPreference

    var body: some View {
        TimelineView(.everyMinute) { context in
            ActivityLogContent(
                entries: log.entries,
                now: context.date,
                accent: Palette.accent(accent.theme),
                clear: { log.clear() }
            )
        }
    }
}

struct ActivityLogContent: View {
    let entries: [ActivityEntry]
    let now: Date
    let accent: Color
    let clear: () -> Void
    var calendar: Calendar = .autoupdatingCurrent
    var locale: Locale = .autoupdatingCurrent

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                Text("No events yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let days = ActivityDay.list(entries, now: now, calendar: calendar)
                        ForEach(days.indices, id: \.self) { index in
                            if index > 0 {
                                Divider()
                            }
                            day(days[index])
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            Divider()
            footer
        }
        .frame(width: ActivityLogWindowController.width)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
    }

    private func day(_ day: ActivityDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(day.title.text(now: now, calendar: calendar, locale: locale))
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(day.entries.indices, id: \.self) { index in
                ActivityLogRow(entry: day.entries[index], accent: accent, time: timeFormatter)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("Last 200 events · kept only on this Mac")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Clear", action: clear)
                .disabled(entries.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
}

private struct ActivityLogRow: View {
    let entry: ActivityEntry
    let accent: Color
    let time: DateFormatter

    var body: some View {
        let row = ActivityRow(entry)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // The widest time of the day sets the column, so 12-hour times with AM and PM line up.
            ZStack(alignment: .leading) {
                Text(verbatim: time.string(from: Self.widestTime(time)))
                    .hidden()
                Text(verbatim: time.string(from: entry.time))
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
            .frame(minWidth: 38, alignment: .leading)
            Image(systemName: row.symbol.systemName)
                .font(.system(size: 12))
                .foregroundStyle(row.symbol.usesAccent ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = row.detail {
                    Text(verbatim: detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 40)
        .accessibilityElement(children: .combine)
    }

    /// 22:58, or 10:58 PM: two-digit hours and minutes in both clocks.
    private static func widestTime(_ formatter: DateFormatter) -> Date {
        let calendar = formatter.calendar ?? .current
        let start = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        return calendar.date(bySettingHour: 22, minute: 58, second: 0, of: start) ?? start
    }
}
