import Foundation

enum WeatherSource: String, Codable {
    case noaa
    case openMeteo

    var label: String {
        switch self {
        case .noaa: return "NOAA"
        case .openMeteo: return "Open-Meteo (fallback)"
        }
    }
}

struct Temperature: Codable, Equatable {
    let celsius: Double
    var fahrenheit: Double { RustCore.celsiusToFahrenheit(celsius) }

    init(celsius: Double) { self.celsius = celsius }
    init(fahrenheit: Double) { self.celsius = RustCore.fahrenheitToCelsius(fahrenheit) }

    var fahrenheitRounded: Int { Int(fahrenheit.rounded()) }
    var celsiusRounded: Int { Int(celsius.rounded()) }
}

/// Everything the UI and widgets display. Stored in the shared cache.
struct WeatherSnapshot: Codable, Equatable {
    var locationName: String
    var latitude: Double
    var longitude: Double
    var source: WeatherSource
    var stationID: String?
    var stationName: String?
    /// Latest valid observation. nil means NO observation; never filled from the forecast.
    var current: Temperature?
    var observedAt: Date?
    var high: Temperature?
    var low: Temperature?
    var fetchedAt: Date
    /// Why `current` is missing, for display.
    var observationNote: String?
}

struct Coordinate: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var name: String?
    var timeZoneID: String? = nil

    /// Fallback when no location is available.
    static let lombard = Coordinate(latitude: 41.88, longitude: -88.02, name: "LOMBARD", timeZoneID: "America/Chicago")
}

enum WeatherError: Error, Equatable, LocalizedError {
    case network(String)
    case badResponse
    case noValidObservation(String)
    case noForecast
    case unsupportedLocation

    var errorDescription: String? {
        switch self {
        case .network(let m): return "Network error: \(m)"
        case .badResponse: return "Unexpected response from weather service."
        case .noValidObservation(let m): return m
        case .noForecast: return "Forecast unavailable."
        case .unsupportedLocation: return "NOAA does not cover this location."
        }
    }
}
