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

    func save(_ snapshot: WeatherSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: Self.snapshotKey) }
    }

    /// Returns nil for missing or corrupt data.
    func load() -> WeatherSnapshot? {
        guard let data = defaults.data(forKey: Self.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
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

    func refresh(for coordinate: Coordinate) async -> Outcome {
        do {
            let snapshot = try await service.fetch(for: coordinate)
            cache.save(snapshot)
            return .fresh(snapshot)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if let cached = cache.load() { return .cached(cached, error: message) }
            return .failed(message)
        }
    }
}
