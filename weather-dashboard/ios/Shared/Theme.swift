import SwiftUI

enum Theme {
    static let background = Color(red: 0.05, green: 0.07, blue: 0.11)
    static let accent = Color.cyan
    static let secondary = Color.white.opacity(0.6)
}

extension Temperature {
    /// "72°F / 22°C"
    var dualText: String { "\(fahrenheitRounded)°F / \(celsiusRounded)°C" }
    /// "47°/8°" (F then C), compact for high/low.
    var pairText: String { "\(fahrenheitRounded)°/\(celsiusRounded)°" }
}

extension Optional where Wrapped == Temperature {
    var fText: String { map { "\($0.fahrenheitRounded)°F" } ?? "—" }
    var cText: String { map { "\($0.celsiusRounded)°C" } ?? "—" }
    var pairText: String { map { $0.pairText } ?? "—" }
}

extension WeatherSnapshot {
    /// Observation age relative to `now`, e.g. "12 min ago".
    func observationAge(now: Date) -> String? {
        guard let t = observedAt else { return nil }
        let minutes = max(0, Int(now.timeIntervalSince(t) / 60))
        return minutes < 1 ? "just now" : (minutes < 90 ? "\(minutes) min ago" : "\(minutes / 60) h ago")
    }
}
