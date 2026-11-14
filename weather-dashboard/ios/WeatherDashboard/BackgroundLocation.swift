import CoreLocation
import WidgetKit

/// With "Always" permission, iOS wakes the app on significant location changes (cell-tower level,
/// roughly every few hundred metres to km). We then update home weather and the widgets.
/// Low battery cost, but iOS decides when it fires.
final class BackgroundLocation: NSObject, CLLocationManagerDelegate {
    static let shared = BackgroundLocation()
    private let manager = CLLocationManager()

    func start() {
        manager.delegate = self
        if manager.authorizationStatus == .authorizedAlways { manager.startMonitoringSignificantLocationChanges() }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways { manager.startMonitoringSignificantLocationChanges() }
        else { manager.stopMonitoringSignificantLocationChanges() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // A manually chosen home location always wins over GPS.
        let cache = WeatherCache()
        if cache.manualLocation != nil { return }
        let c = Coordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, name: nil,
                           timeZoneID: TimeZone.current.identifier)
        cache.saveLocation(c)
        cache.updateHome(c)
        Task {
            _ = await WeatherRefresher.refresh(cities: cache.loadCities(), cache: cache, maxAge: 0)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
