import SwiftUI
import CoreLocation

struct DashboardView: View {
    @StateObject private var model = DashboardModel()

    var body: some View {
        ZStack {
            Color(red: 0.09, green: 0.14, blue: 0.23).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                Text("LOMBARD").font(.headline).foregroundStyle(.cyan)
                if let weather = model.weather {
                    Text("\(weather.fahrenheit)°F / \(weather.celsius)°C")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    HStack {
                        Text("HIGH \(weather.high)°F")
                        Spacer()
                        Text("LOW \(weather.low)°F")
                    }.font(.headline).foregroundStyle(.white)
                } else {
                    ProgressView().tint(.white)
                    Text(model.error ?? "Loading weather…").foregroundStyle(.white.opacity(0.7))
                }
                Divider().overlay(.white.opacity(0.25))
                clockRow("Guntur", zone: "Asia/Kolkata")
                clockRow("London", zone: "Europe/London")
                Spacer()
                Button { Task { await model.refresh() } } label: {
                    Label("Refresh weather", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }.tint(.cyan)
            }
            .padding(24)
        }
        .task { await model.refresh() }
    }

    private func clockRow(_ city: String, zone: String) -> some View {
        HStack {
            Text(city).font(.title3.weight(.semibold)).foregroundStyle(.white)
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(context.date.formatted(.dateTime.hour().minute().timeZone(TimeZone(identifier: zone)!)))
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

struct WeatherSnapshot {
    let fahrenheit: Int
    let celsius: Int
    let high: Int
    let low: Int
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published var weather: WeatherSnapshot?
    @Published var error: String?
    private let locationManager = CLLocationManager()

    func refresh() async {
        do {
            let coordinate = try await currentCoordinate()
            let url = URL(string: "https://api.weather.gov/points/\(coordinate.latitude),\(coordinate.longitude)")!
            var request = URLRequest(url: url)
            request.setValue("WeatherDashboard/1.0 contact: user@example.com", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            let point = try JSONDecoder().decode(PointResponse.self, from: data)

            async let forecastData = fetch(point.properties.forecast)
            async let stationsData = fetch(point.properties.observationStations)
            let (forecast, stations) = try await (forecastData, stationsData)

            let forecastResponse = try JSONDecoder().decode(ForecastResponse.self, from: forecast)
            let stationResponse = try JSONDecoder().decode(StationsResponse.self, from: stations)

            var currentC: Double?
            for station in stationResponse.features.prefix(5) {
                guard let observationURL = URL(string: "https://api.weather.gov/stations/\(station.properties.stationIdentifier)/observations/latest") else { continue }
                if let data = try? await fetch(observationURL),
                   let observation = try? JSONDecoder().decode(ObservationResponse.self, from: data),
                   let value = observation.properties.temperature.value,
                   value > -90 && value < 65 {
                    currentC = value
                    break
                }
            }
            guard let c = currentC else { throw URLError(.cannotParseResponse) }
            let day = forecastResponse.properties.periods.first(where: { $0.isDaytime })
            let night = forecastResponse.properties.periods.first(where: { !$0.isDaytime })
            let f = c * 9 / 5 + 32
            weather = WeatherSnapshot(fahrenheit: Int(f.rounded()), celsius: Int(c.rounded()),
                                      high: day?.temperature ?? 0, low: night?.temperature ?? 0)
            error = nil
        } catch {
            self.error = "Weather unavailable. Tap refresh to retry."
        }
    }

    private func currentCoordinate() async throws -> CLLocationCoordinate2D {
        let manager = CLLocationManager()
        manager.requestWhenInUseAuthorization()
        return CLLocationCoordinate2D(latitude: 41.88, longitude: -88.02)
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("WeatherDashboard/1.0 contact: user@example.com", forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: request).0
    }
}

struct PointResponse: Decodable { let properties: PointProperties }
struct PointProperties: Decodable { let forecast: URL; let observationStations: URL }
struct ForecastResponse: Decodable { let properties: ForecastProperties }
struct ForecastProperties: Decodable { let periods: [ForecastPeriod] }
struct ForecastPeriod: Decodable { let isDaytime: Bool; let temperature: Int; let temperatureUnit: String; let shortForecast: String }
struct StationsResponse: Decodable { let features: [StationFeature] }
struct StationFeature: Decodable { let properties: StationProperties }
struct StationProperties: Decodable { let stationIdentifier: String; let name: String }
struct ObservationResponse: Decodable { let properties: ObservationProperties }
struct ObservationProperties: Decodable { let temperature: Measurement }
struct Measurement: Decodable { let value: Double? }
