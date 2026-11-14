import Foundation

/// A city shown on the dashboard and widget. The `isHome` city follows GPS / the manual location.
struct City: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var zoneID: String
    var latitude: Double
    var longitude: Double
    var isHome: Bool = false

    var clock: CityClock { CityClock(name: name, zoneID: zoneID) }
    var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude, name: name, timeZoneID: zoneID) }

    static let homeID = "home"
    static let maxCities = 6

    static let defaults: [City] = [
        City(id: homeID, name: "LOMBARD", zoneID: "America/Chicago", latitude: 41.88, longitude: -88.02, isHome: true),
        City(id: "guntur", name: "Guntur", zoneID: "Asia/Kolkata", latitude: 16.3067, longitude: 80.4365),
        City(id: "london", name: "London", zoneID: "Europe/London", latitude: 51.5074, longitude: -0.1278),
    ]
}
