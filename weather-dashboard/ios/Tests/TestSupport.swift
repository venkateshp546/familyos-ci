import Foundation

final class MockClient: HTTPClient {
    var responses: [String: Data] = [:]
    var failAll = false
    private(set) var requested: [String] = []

    func data(from url: URL) async throws -> Data {
        requested.append(url.absoluteString)
        if failAll { throw WeatherError.network("offline") }
        let match = responses.keys.filter { url.absoluteString.contains($0) }.max { $0.count < $1.count }
        if let match { return responses[match]! }
        throw WeatherError.network("HTTP 404")
    }
}

enum Fixtures {
    static let now = ISO8601.parse("2026-11-14T18:00:00Z")!

    static let point = """
    {"properties":{"forecast":"https://api.weather.gov/gridpoints/LOT/1,1/forecast",
    "observationStations":"https://api.weather.gov/gridpoints/LOT/1,1/stations",
    "timeZone":"America/Chicago",
    "relativeLocation":{"properties":{"city":"Lombard","state":"IL"}}}}
    """.data(using: .utf8)!

    // Far station listed first, near station second: sorting must fix the order.
    static let stations = """
    {"features":[
     {"geometry":{"coordinates":[-87.0,41.0]},"properties":{"stationIdentifier":"KFAR","name":"Far"}},
     {"geometry":{"coordinates":[-88.05,41.90]},"properties":{"stationIdentifier":"KNEAR","name":"Near"}}]}
    """.data(using: .utf8)!

    static func observation(temp: String, time: String, qc: String = "V", unit: String = "wmoUnit:degC") -> Data {
        """
        {"properties":{"timestamp":"\(time)","temperature":{"value":\(temp),"unitCode":"\(unit)","qualityControl":"\(qc)"}}}
        """.data(using: .utf8)!
    }

    /// Forecast for 2026-11-14 in America/Chicago (UTC-6).
    static let forecast = """
    {"properties":{"periods":[
     {"startTime":"2026-11-14T10:00:00-06:00","endTime":"2026-11-14T18:00:00-06:00","isDaytime":true,"temperature":58,"temperatureUnit":"F"},
     {"startTime":"2026-11-14T18:00:00-06:00","endTime":"2026-11-15T06:00:00-06:00","isDaytime":false,"temperature":41,"temperatureUnit":"F"},
     {"startTime":"2026-11-15T06:00:00-06:00","endTime":"2026-11-15T18:00:00-06:00","isDaytime":true,"temperature":50,"temperatureUnit":"F"}]}}
    """.data(using: .utf8)!

    static func client(observationNear: Data, forecast: Data = Fixtures.forecast) -> MockClient {
        let c = MockClient()
        c.responses["/points/"] = point
        c.responses["/forecast"] = forecast
        c.responses["/stations/KNEAR/observations/latest"] = observationNear
        c.responses["/stations/KFAR/observations/latest"] = observation(temp: "10.0", time: "2026-11-14T17:50:00Z")
        c.responses["/stations"] = stations
        return c
    }

    static let coordinate = Coordinate(latitude: 41.88, longitude: -88.02, name: nil)

    static func service(_ client: HTTPClient, fallback: Bool = false) -> WeatherService {
        var s = WeatherService(client: client, now: { now })
        s.allowOpenMeteoFallback = fallback
        return s
    }
}
