import Foundation

public enum ScheduledWake {
    /// The `minuteOfDay` that cancels the schedule.
    public static let off = -1
    public static let minutes = 0...1439

    /// Reads `HH:MM` (two digits each) or `off` into a minute of the day, or `off`; nil when neither.
    public static func minuteOfDay(from text: String) -> Int? {
        if text == "off" { return off }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    /// The field the status commands print: `wake=off`, `wake=unknown` or the local times, earliest first.
    public static func statusField(_ wakes: [Date]?, timeZone: TimeZone = .current) -> String {
        guard let wakes else { return "wake=unknown" }
        guard !wakes.isEmpty else { return "wake=off" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return "wake=" + wakes.sorted().map(formatter.string(from:)).joined(separator: ",")
    }
}

/// Wake times as whole seconds since 1970, newline-separated, earliest first.
public enum ScheduledWakeWire {
    public static func encode(_ wakes: [Date]) -> String {
        wakes.sorted()
            .map { String(Int64($0.timeIntervalSince1970.rounded())) }
            .joined(separator: "\n")
    }

    /// Nil when any line is not a number.
    public static func decode(_ text: String) -> [Date]? {
        guard !text.isEmpty else { return [] }
        var wakes: [Date] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let seconds = Int64(line) else { return nil }
            wakes.append(Date(timeIntervalSince1970: TimeInterval(seconds)))
        }
        return wakes.sorted()
    }
}
