import Foundation

struct WeatherService {
    var client: HTTPClient = URLSessionClient()
    var now: () -> Date = Date.init
    /// Observations older than this are rejected.
    var maxObservationAge: TimeInterval = 90 * 60
    var maxStationsToTry = 8
    var allowOpenMeteoFallback = true
    /// Tried first when set. Any failure falls through to NOAA / Open-Meteo.
    var weatherKitFetch: WeatherKitProvider.Fetcher? = nil

    // MARK: Public entry point

    func fetch(for coordinate: Coordinate) async throws -> WeatherSnapshot {
        if let wk = weatherKitFetch, let snapshot = try? await wk(coordinate) { return snapshot }
        do {
            return try await fetchNOAA(for: coordinate)
        } catch let noaaError as WeatherError {
            guard allowOpenMeteoFallback, shouldFallback(from: noaaError) else { throw noaaError }
            return try await fetchOpenMeteo(for: coordinate)
        }
    }

    /// Only structural/coverage/network failures fall back; a NOAA snapshot with a
    /// missing observation is returned as-is (with a note) rather than substituted.
    private func shouldFallback(from error: WeatherError) -> Bool {
        switch error {
        case .unsupportedLocation, .network, .badResponse: return true
        case .noValidObservation, .noForecast: return false
        }
    }

    // MARK: NOAA

    func fetchNOAA(for coordinate: Coordinate) async throws -> WeatherSnapshot {
        let pointURL = URL(string: String(format: "https://api.weather.gov/points/%.4f,%.4f", coordinate.latitude, coordinate.longitude))!
        let point = try decode(NOAAPointResponse.self, from: try await client.data(from: pointURL))
        let zone = point.properties.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current

        // Forecast is best effort; the observation is the primary datum.
        let forecast = try? decode(NOAAForecastResponse.self, from: try await client.data(from: point.properties.forecast))
        let (high, low) = Self.todayHighLow(periods: forecast?.properties.periods ?? [], now: now(), timeZone: zone)

        let stations = try decode(NOAAStationsResponse.self, from: try await client.data(from: point.properties.observationStations))
        let (observation, note) = await nearestValidObservation(stations: stations, coordinate: coordinate)

        let rel = point.properties.relativeLocation?.properties
        let name = coordinate.name ?? rel?.city?.uppercased() ?? "CURRENT LOCATION"

        if observation == nil && high == nil && low == nil {
            throw WeatherError.noValidObservation(note ?? "No usable observation.")
        }
        return WeatherSnapshot(
            locationName: name,
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            source: .noaa,
            stationID: observation?.id, stationName: observation?.name,
            current: observation.map { Temperature(celsius: $0.celsius) },
            observedAt: observation?.time,
            high: high, low: low,
            fetchedAt: now(),
            observationNote: observation == nil ? note : nil)
    }

    struct ValidObservation { let id: String; let name: String?; let celsius: Double; let time: Date }

    func nearestValidObservation(stations: NOAAStationsResponse, coordinate: Coordinate) async -> (ValidObservation?, String?) {
        let usable = stations.features.filter { $0.latitude != nil && $0.longitude != nil }
        let order = RustCore.sortByDistance(
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            points: usable.map { (lat: $0.latitude!, lon: $0.longitude!) })
        var lastReason = "No observation stations found nearby."
        for index in order.prefix(maxStationsToTry) {
            let station = usable[index]
            let id = station.properties.stationIdentifier
            guard let url = URL(string: "https://api.weather.gov/stations/\(id)/observations/latest"),
                  let data = try? await client.data(from: url),
                  let obs = try? decode(NOAAObservationResponse.self, from: data) else {
                lastReason = "Station \(id) did not respond."
                continue
            }
            guard let time = obs.timestamp else { lastReason = "Station \(id) reported no timestamp."; continue }
            let status = RustCore.observationStatus(
                temperatureC: obs.temperatureCelsius,
                ageSeconds: now().timeIntervalSince(time),
                maxAgeSeconds: maxObservationAge)
            switch status {
            case .ok:
                return (ValidObservation(id: id, name: station.properties.name, celsius: obs.temperatureCelsius!, time: time), nil)
            case .missing: lastReason = "Station \(id) reported no temperature."
            case .outOfRange: lastReason = "Station \(id) reported an implausible temperature."
            case .future: lastReason = "Station \(id) reported a future timestamp."
            case .stale: lastReason = "Latest observation from \(id) is stale."
            }
        }
        return (nil, lastReason)
    }

    /// Today's high/low from official forecast periods, using the location's local calendar day.
    static func todayHighLow(periods: [NOAAForecastResponse.Period], now: Date, timeZone: TimeZone) -> (Temperature?, Temperature?) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        func isToday(_ s: String) -> Bool {
            guard let d = ISO8601.parse(s) else { return false }
            return cal.isDate(d, inSameDayAs: now)
        }
        let highs = periods.filter { $0.isDaytime && isToday($0.startTime) }.compactMap { $0.celsius }
        let high = highs.max { $0.celsius < $1.celsius }
        // Prefer the night that starts today, else a pre-dawn period that ends today.
        var lows = periods.filter { !$0.isDaytime && isToday($0.startTime) }.compactMap { $0.celsius }
        if lows.isEmpty { lows = periods.filter { !$0.isDaytime && isToday($0.endTime) }.compactMap { $0.celsius } }
        let low = lows.min { $0.celsius < $1.celsius }
        return (high, low)
    }

    // MARK: Open-Meteo fallback

    func fetchOpenMeteo(for c: Coordinate) async throws -> WeatherSnapshot {
        let url = URL(string: String(format: "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&current=temperature_2m&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=auto", c.latitude, c.longitude))!
        let r = try decode(OpenMeteoResponse.self, from: try await client.data(from: url))

        var observed: Date?
        if let t = r.current?.time {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: r.utc_offset_seconds ?? 0)
            f.dateFormat = "yyyy-MM-dd'T'HH:mm"
            observed = f.date(from: t)
        }
        var current: Temperature?
        var note: String? = "Open-Meteo reported no current temperature."
        if let v = r.current?.temperature_2m, let observed {
            let status = RustCore.observationStatus(temperatureC: v, ageSeconds: now().timeIntervalSince(observed), maxAgeSeconds: maxObservationAge)
            if status == .ok { current = Temperature(celsius: v); note = nil } else { note = "Open-Meteo reading rejected." }
        }
        let hi = r.daily?.temperature_2m_max?.first.flatMap { $0 }.map { Temperature(celsius: $0) }
        let lo = r.daily?.temperature_2m_min?.first.flatMap { $0 }.map { Temperature(celsius: $0) }
        if current == nil && hi == nil && lo == nil { throw WeatherError.badResponse }
        return WeatherSnapshot(
            locationName: c.name ?? "CURRENT LOCATION",
            latitude: c.latitude, longitude: c.longitude,
            source: .openMeteo, stationID: nil, stationName: nil,
            current: current, observedAt: current == nil ? nil : observed,
            high: hi, low: lo, fetchedAt: now(), observationNote: note)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw WeatherError.badResponse }
    }
}
