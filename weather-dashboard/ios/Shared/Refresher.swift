import Foundation

/// Shared refresh used by the widget timeline, the widget refresh button and background app refresh.
enum WeatherRefresher {
    /// Returns the best available snapshot per city. Cities whose cache is younger than `maxAge`
    /// are not re-fetched (`maxAge: 0` forces a fetch). Failures fall back to the cached snapshot.
    static func refresh(cities: [City],
                        cache: WeatherCache = WeatherCache(),
                        maxAge: TimeInterval,
                        now: Date = Date(),
                        service: WeatherService? = nil) async -> [String: WeatherSnapshot] {
        var svc = service ?? WeatherService()
        if service == nil {
            svc.allowOpenMeteoFallback = cache.fallbackEnabled
            svc.weatherKitFetch = WeatherKitProvider.fetcher(cache: cache)
        }
        let repo = WeatherRepository(service: svc, cache: cache)
        var result: [String: WeatherSnapshot] = [:]
        await withTaskGroup(of: (String, WeatherSnapshot?).self) { group in
            for city in cities {
                group.addTask {
                    let cached = cache.load(cityID: city.id)
                    if maxAge > 0, let cached, now.timeIntervalSince(cached.fetchedAt) <= maxAge { return (city.id, cached) }
                    switch await repo.refresh(for: city.coordinate, cityID: city.id) {
                    case .fresh(let s): return (city.id, s)
                    case .cached(let s, _): return (city.id, s)
                    case .failed: return (city.id, nil)
                    }
                }
            }
            for await (id, s) in group { if let s { result[id] = s } }
        }
        return result
    }
}
