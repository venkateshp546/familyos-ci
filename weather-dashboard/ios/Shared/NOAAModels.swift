import Foundation

// MARK: - NOAA api.weather.gov payloads

struct NOAAPointResponse: Decodable {
    struct Properties: Decodable {
        struct Relative: Decodable {
            struct Props: Decodable { let city: String?; let state: String? }
            let properties: Props?
        }
        let forecast: URL
        let observationStations: URL
        let timeZone: String?
        let relativeLocation: Relative?
    }
    let properties: Properties
}

struct NOAAStationsResponse: Decodable {
    struct Feature: Decodable {
        struct Geometry: Decodable { let coordinates: [Double] }
        struct Props: Decodable { let stationIdentifier: String; let name: String? }
        let geometry: Geometry?
        let properties: Props
        var longitude: Double? { geometry.flatMap { $0.coordinates.count >= 2 ? $0.coordinates[0] : nil } }
        var latitude: Double? { geometry.flatMap { $0.coordinates.count >= 2 ? $0.coordinates[1] : nil } }
    }
    let features: [Feature]
}

struct NOAAObservationResponse: Decodable {
    struct QuantitativeValue: Decodable {
        let value: Double?
        let unitCode: String?
        let qualityControl: String?
    }
    struct Properties: Decodable {
        let timestamp: String?
        let temperature: QuantitativeValue?
    }
    let properties: Properties

    /// Temperature in Celsius, nil when absent or rejected by NOAA QC ("X" = failed).
    var temperatureCelsius: Double? {
        guard let t = properties.temperature, let v = t.value, v.isFinite else { return nil }
        if t.qualityControl == "X" { return nil }
        let unit = (t.unitCode ?? "").lowercased()
        if unit.contains("degf") { return RustCore.fahrenheitToCelsius(v) }
        if unit.contains("kelvin") { return v - 273.15 }
        return v
    }

    var timestamp: Date? { properties.timestamp.flatMap(ISO8601.parse) }
}

struct NOAAForecastResponse: Decodable {
    struct Period: Decodable {
        let startTime: String
        let endTime: String
        let isDaytime: Bool
        let temperature: Double?
        let temperatureUnit: String?

        var celsius: Temperature? {
            guard let t = temperature else { return nil }
            return temperatureUnit?.uppercased() == "C" ? Temperature(celsius: t) : Temperature(fahrenheit: t)
        }
    }
    struct Properties: Decodable { let periods: [Period]? }
    let properties: Properties
}

enum ISO8601 {
    static func parse(_ s: String) -> Date? {
        let a = ISO8601DateFormatter()
        a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = a.date(from: s) { return d }
        let b = ISO8601DateFormatter()
        b.formatOptions = [.withInternetDateTime]
        return b.date(from: s)
    }
}

// MARK: - Open-Meteo fallback payload

struct OpenMeteoResponse: Decodable {
    struct Current: Decodable { let temperature_2m: Double?; let time: String? }
    struct Daily: Decodable { let temperature_2m_max: [Double?]?; let temperature_2m_min: [Double?]? }
    let current: Current?
    let daily: Daily?
    let utc_offset_seconds: Int?
}
