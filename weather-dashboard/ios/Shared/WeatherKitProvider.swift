import CoreLocation
import Foundation
#if canImport(WeatherKit)
import WeatherKit
#endif

/// Optional Apple WeatherKit source. Works only when the signed app carries the WeatherKit
/// entitlement; otherwise every call fails and the app falls back to NOAA / Open-Meteo.
enum WeatherKitProvider {
    typealias Fetcher = (Coordinate) async throws -> WeatherSnapshot

    /// After a failure WeatherKit is not retried for this long, so unsupported installs stay fast.
    static let retryDelay: TimeInterval = 6 * 3600

    static func fetcher(cache: WeatherCache, now: @escaping () -> Date = Date.init) -> Fetcher? {
        #if canImport(WeatherKit)
        return { coordinate in
            guard cache.weatherKitEnabled, now() >= cache.weatherKitRetryAfter else { throw WeatherError.unsupportedLocation }
            do {
                return try await fetch(coordinate, now: now())
            } catch {
                cache.weatherKitRetryAfter = now().addingTimeInterval(retryDelay)
                throw WeatherError.network("WeatherKit unavailable")
            }
        }
        #else
        return nil
        #endif
    }

    #if canImport(WeatherKit)
    private static func fetch(_ c: Coordinate, now: Date) async throws -> WeatherSnapshot {
        let location = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let (current, daily) = try await WeatherKit.WeatherService.shared.weather(for: location, including: .current, .daily)
        let celsius = current.temperature.converted(to: .celsius).value
        guard RustCore.observationStatus(temperatureC: celsius, ageSeconds: now.timeIntervalSince(current.date), maxAgeSeconds: 90 * 60) == .ok else {
            throw WeatherError.badResponse
        }
        var name = c.name
        if name == nil {
            name = (try? await CLGeocoder().reverseGeocodeLocation(location))?.first?.locality?.uppercased()
        }
        let day = daily.forecast.first
        return WeatherSnapshot(
            locationName: name ?? "CURRENT LOCATION",
            latitude: c.latitude, longitude: c.longitude, source: .weatherKit,
            stationID: nil, stationName: nil,
            current: Temperature(celsius: celsius), observedAt: current.date,
            high: day.map { Temperature(celsius: $0.highTemperature.converted(to: .celsius).value) },
            low: day.map { Temperature(celsius: $0.lowTemperature.converted(to: .celsius).value) },
            fetchedAt: now, observationNote: nil)
    }
    #endif
}
