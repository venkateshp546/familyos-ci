import Combine
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class DashboardModel: ObservableObject {
    @Published var cities: [City]
    @Published var snapshots: [String: WeatherSnapshot] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var manualLocation: Coordinate?
    @Published var manualError: String?
    @Published var cityError: String?
    @Published var useFallback: Bool { didSet { cache.fallbackEnabled = useFallback } }

    let location = LocationProvider()
    private let cache = WeatherCache()
    private static let legacyManualKey = "manual.location.v1"
    private var started = false
    private var bag = Set<AnyCancellable>()

    init() {
        cities = cache.loadCities()
        useFallback = cache.fallbackEnabled
        for c in cities { snapshots[c.id] = cache.load(cityID: c.id) }
        location.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        manualLocation = cache.manualLocation
        if manualLocation == nil, let data = UserDefaults.standard.data(forKey: Self.legacyManualKey),
           let legacy = try? JSONDecoder().decode(Coordinate.self, from: data) {
            manualLocation = legacy
            cache.manualLocation = legacy
        }
    }

    func start() {
        guard !started else { return }
        started = true
        if manualLocation == nil { location.start() }
        Task { await refresh() }
    }

    var effectiveCoordinate: Coordinate {
        LocationResolver.resolve(manual: manualLocation, gps: location.coordinate, lastKnown: cache.loadLocation())
    }

    func displayName(_ city: City) -> String {
        city.isHome ? (snapshots[city.id]?.locationName ?? city.name) : city.name
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let home = effectiveCoordinate
        cache.saveLocation(home)
        updateHome(home)

        var service = WeatherService()
        service.allowOpenMeteoFallback = useFallback
        let repo = WeatherRepository(service: service, cache: cache)
        var errors: [String] = []
        let targets = cities.map { ($0, $0.isHome ? home : $0.coordinate) }

        // Detached so SwiftUI cancelling the pull-to-refresh / .task context cannot abort the requests.
        let results = await Task.detached { await Self.fetchAll(targets: targets, repo: repo) }.value
        for (city, outcome) in results {
            switch outcome {
            case .fresh(let s): snapshots[city.id] = s
            case .cached(let s, let e): snapshots[city.id] = s; errors.append("\(city.name): \(e)")
            case .failed(let e): errors.append("\(city.name): \(e)")
            }
        }
        errorMessage = errors.isEmpty ? nil : "Some weather could not be updated; showing saved data where available. \(errors[0])"
        WidgetCenter.shared.reloadAllTimelines()
    }

    nonisolated private static func fetchAll(targets: [(City, Coordinate)], repo: WeatherRepository) async -> [(City, WeatherRepository.Outcome)] {
        await withTaskGroup(of: (City, WeatherRepository.Outcome).self) { group in
            for (city, coordinate) in targets {
                group.addTask { (city, await repo.refresh(for: coordinate, cityID: city.id)) }
            }
            var out: [(City, WeatherRepository.Outcome)] = []
            for await item in group { out.append(item) }
            return out
        }
    }

    private func updateHome(_ c: Coordinate) {
        guard let i = cities.firstIndex(where: { $0.isHome }) else { return }
        cities[i].latitude = c.latitude
        cities[i].longitude = c.longitude
        if let n = c.name { cities[i].name = n }
        if let z = c.timeZoneID { cities[i].zoneID = z }
        cache.saveCities(cities)
    }

    /// Re-fetch once GPS delivers a coordinate.
    func gpsUpdated() async { if manualLocation == nil { await refresh() } }

    func setManual(_ text: String) async {
        manualError = nil
        do {
            var c = try await LocationProvider.geocode(text)
            c.name = c.name?.uppercased()
            manualLocation = c
            cache.manualLocation = c
            await refresh()
        } catch {
            manualError = "Could not find that place."
        }
    }

    func useGPS() {
        manualLocation = nil
        cache.manualLocation = nil
        UserDefaults.standard.removeObject(forKey: Self.legacyManualKey)
        location.start()
        Task { await refresh() }
    }

    // MARK: Cities

    func addCity(_ text: String) async {
        cityError = nil
        guard cities.count < City.maxCities else { cityError = "Up to \(City.maxCities) cities."; return }
        do {
            let c = try await LocationProvider.geocode(text)
            let city = City(id: UUID().uuidString, name: c.name ?? text,
                            zoneID: c.timeZoneID ?? TimeZone.current.identifier,
                            latitude: c.latitude, longitude: c.longitude)
            cities.append(city)
            cache.saveCities(cities)
            await refresh()
        } catch {
            cityError = "Could not find that place."
        }
    }

    func removeCities(at offsets: IndexSet) {
        let removable = offsets.map { cities[$0] }.filter { !$0.isHome }
        for c in removable {
            cities.removeAll { $0.id == c.id }
            snapshots[c.id] = nil
            cache.removeSnapshot(cityID: c.id)
        }
        cache.saveCities(cities)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
