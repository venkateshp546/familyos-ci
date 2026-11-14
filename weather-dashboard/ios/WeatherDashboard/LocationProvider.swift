import CoreLocation
import Foundation

@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var access: LocationAccess
    @Published private(set) var coordinate: Coordinate?
    @Published private(set) var failure: String?

    private let manager = CLLocationManager()

    override init() {
        access = LocationAccess(status: manager.authorizationStatus, servicesEnabled: true)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        access = LocationAccess(status: manager.authorizationStatus, servicesEnabled: true)
        switch access {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorized: manager.requestLocation()
        default: break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.access = LocationAccess(status: status, servicesEnabled: true)
            if self.access == .authorized { manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.failure = nil
            self.coordinate = Coordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, name: nil)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.failure = message }
    }

    /// Manual fallback: resolve a place name to a coordinate.
    static func geocode(_ text: String) async throws -> Coordinate {
        let marks = try await CLGeocoder().geocodeAddressString(text)
        guard let m = marks.first, let loc = m.location else { throw WeatherError.badResponse }
        let name = (m.locality ?? m.name ?? text).uppercased()
        return Coordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, name: name)
    }
}
