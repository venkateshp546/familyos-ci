import Foundation
import WeatherCore

/// Thin Swift wrappers over the Rust `weather_core` static library.
enum RustCore {
    enum ObservationStatus: Int32 {
        case ok = 0, missing = 1, outOfRange = 2, future = 3, stale = 4
    }

    static func celsiusToFahrenheit(_ c: Double) -> Double { weather_celsius_to_fahrenheit(c) }
    static func fahrenheitToCelsius(_ f: Double) -> Double { weather_fahrenheit_to_celsius(f) }

    static func observationStatus(temperatureC: Double?, ageSeconds: Double, maxAgeSeconds: Double) -> ObservationStatus {
        let code = weather_observation_status(temperatureC ?? .nan, ageSeconds, maxAgeSeconds)
        return ObservationStatus(rawValue: code) ?? .missing
    }

    static func distanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        weather_distance_km(lat1, lon1, lat2, lon2)
    }

    /// Indices of `points` ordered nearest-first relative to the target.
    static func sortByDistance(latitude: Double, longitude: Double, points: [(lat: Double, lon: Double)]) -> [Int] {
        guard !points.isEmpty else { return [] }
        let lats = points.map { $0.lat }
        let lons = points.map { $0.lon }
        var order = [UInt](repeating: 0, count: points.count)
        let written = lats.withUnsafeBufferPointer { la in
            lons.withUnsafeBufferPointer { lo in
                order.withUnsafeMutableBufferPointer { out in
                    weather_sort_by_distance(latitude, longitude, la.baseAddress, lo.baseAddress, UInt(points.count), out.baseAddress)
                }
            }
        }
        guard written == UInt(points.count) else { return Array(points.indices) }
        return order.map { Int($0) }
    }
}
