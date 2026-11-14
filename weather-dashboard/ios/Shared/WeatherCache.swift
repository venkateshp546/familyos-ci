import Foundation

enum AppGroup {
    static let identifier = "group.com.vtsapps.weatherdashboard"
}

/// Last-successful snapshot + chosen location, shared with the widget via an App Group.
/// Falls back to standard defaults when the App Group is unavailable (e.g. unsigned builds).
struct WeatherCache {
    private let defaults: UserDefaults
    static let snapshotKey = "weather.snapshot.v1"
    static let locationKey = "weather.location.v1"

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    static let citiesKey = "weather.cities.v1"
    static let fallbackKey = "useOpenMeteoFallback"

    /// The home city keeps the original key so older caches stay readable.
    private func key(_ cityID: String) -> String {
        cityID == City.homeID ? Self.snapshotKey : "\(Self.snapshotKey).\(cityID)"
    }

    func save(_ snapshot: WeatherSnapshot, cityID: String = City.homeID) {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: key(cityID)) }
    }

    /// Returns nil for missing or corrupt data.
    func load(cityID: String = City.homeID) -> WeatherSnapshot? {
        guard let data = defaults.data(forKey: key(cityID)) else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
    }

    func removeSnapshot(cityID: String) { defaults.removeObject(forKey: key(cityID)) }

    func saveCities(_ cities: [City]) {
        if let data = try? JSONEncoder().encode(cities) { defaults.set(data, forKey: Self.citiesKey) }
    }

    /// Defaults when nothing (or corrupt data) is stored. Always contains a home city.
    func loadCities() -> [City] {
        guard let data = defaults.data(forKey: Self.citiesKey),
              var list = try? JSONDecoder().decode([City].self, from: data), !list.isEmpty else { return City.defaults }
        if !list.contains(where: { $0.isHome }) { list.insert(City.defaults[0], at: 0) }
        return list
    }

    var fallbackEnabled: Bool {
        get { defaults.object(forKey: Self.fallbackKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.fallbackKey) }
    }

    func saveLocation(_ c: Coordinate) {
        if let data = try? JSONEncoder().encode(c) { defaults.set(data, forKey: Self.locationKey) }
    }

    func loadLocation() -> Coordinate? {
        guard let data = defaults.data(forKey: Self.locationKey) else { return nil }
        return try? JSONDecoder().decode(Coordinate.self, from: data)
    }

    func clear() {
        defaults.removeObject(forKey: Self.snapshotKey)
        defaults.removeObject(forKey: Self.locationKey)
        defaults.removeObject(forKey: Self.citiesKey)
    }
}

/// Fetch with cache write-through and cache recovery on failure.
struct WeatherRepository {
    var service: WeatherService
    var cache: WeatherCache

    enum Outcome: Equatable {
        case fresh(WeatherSnapshot)
        /// Network failed; showing last successful data.
        case cached(WeatherSnapshot, error: String)
        case failed(String)
    }

    func refresh(for coordinate: Coordinate, cityID: String = City.homeID) async -> Outcome {
        do {
            let snapshot = try await service.fetch(for: coordinate)
            cache.save(snapshot, cityID: cityID)
            return .fresh(snapshot)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if let cached = cache.load(cityID: cityID) { return .cached(cached, error: message) }
            return .failed(message)
        }
    }
}
