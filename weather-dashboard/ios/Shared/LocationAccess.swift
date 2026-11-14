import CoreLocation

/// Pure mapping of CoreLocation authorization into what the UI needs.
enum LocationAccess: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case servicesDisabled

    init(status: CLAuthorizationStatus, servicesEnabled: Bool) {
        guard servicesEnabled else { self = .servicesDisabled; return }
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .denied
        }
    }

    /// True when only the manual location can be used.
    var needsManualFallback: Bool {
        switch self {
        case .denied, .restricted, .servicesDisabled: return true
        case .notDetermined, .authorized: return false
        }
    }

    var message: String? {
        switch self {
        case .denied: return "Location access denied. Enable it in Settings or set a location manually."
        case .restricted: return "Location access is restricted on this device. Set a location manually."
        case .servicesDisabled: return "Location Services are off. Set a location manually."
        case .notDetermined, .authorized: return nil
        }
    }
}

/// Picks which coordinate to use: manual override > GPS > last known > Lombard.
enum LocationResolver {
    static func resolve(manual: Coordinate?, gps: Coordinate?, lastKnown: Coordinate?) -> Coordinate {
        manual ?? gps ?? lastKnown ?? .lombard
    }
}
