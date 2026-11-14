import Combine
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class DashboardModel: ObservableObject {
    @Published var snapshot: WeatherSnapshot?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var manualLocation: Coordinate?
    @Published var manualError: String?
    @AppStorage("useOpenMeteoFallback") var useFallback = true

    let location = LocationProvider()
    private let cache = WeatherCache()
    private static let manualKey = "manual.location.v1"
    private var started = false
    private var bag = Set<AnyCancellable>()

    init() {
        snapshot = cache.load()
        location.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        if let data = UserDefaults.standard.data(forKey: Self.manualKey) {
            manualLocation = try? JSONDecoder().decode(Coordinate.self, from: data)
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

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let coordinate = effectiveCoordinate
        cache.saveLocation(coordinate)
        var service = WeatherService()
        service.allowOpenMeteoFallback = useFallback
        switch await WeatherRepository(service: service, cache: cache).refresh(for: coordinate) {
        case .fresh(let s):
            snapshot = s; errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
        case .cached(let s, let error):
            snapshot = s; errorMessage = "Showing last saved weather. \(error)"
        case .failed(let error):
            errorMessage = error
        }
    }

    /// Re-fetch once GPS delivers a coordinate.
    func gpsUpdated() async { if manualLocation == nil { await refresh() } }

    func setManual(_ text: String) async {
        manualError = nil
        do {
            let c = try await LocationProvider.geocode(text)
            manualLocation = c
            UserDefaults.standard.set(try? JSONEncoder().encode(c), forKey: Self.manualKey)
            await refresh()
        } catch {
            manualError = "Could not find that place."
        }
    }

    func useGPS() {
        manualLocation = nil
        UserDefaults.standard.removeObject(forKey: Self.manualKey)
        location.start()
        Task { await refresh() }
    }
}
