import Foundation

struct CityClock: Identifiable, Equatable {
    let name: String
    let zoneID: String
    var id: String { zoneID }
    var timeZone: TimeZone { TimeZone(identifier: zoneID) ?? .gmt }

    static let guntur = CityClock(name: "Guntur", zoneID: "Asia/Kolkata")
    static let london = CityClock(name: "London", zoneID: "Europe/London")
    static let all = [guntur, london]

    /// e.g. "6:05 PM" or "6:05:09 PM". Zone rules (DST etc.) come from the system tz database.
    func string(at date: Date, seconds: Bool = false) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = seconds ? "h:mm:ss a" : "h:mm a"
        return f.string(from: date)
    }

    func abbreviation(at date: Date) -> String {
        timeZone.abbreviation(for: date) ?? zoneID
    }
}
