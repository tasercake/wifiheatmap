import CoreLocation

@MainActor
final class LocationAuthManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isDenied = false
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            isDenied = true
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.isDenied = manager.authorizationStatus == .denied
                         || manager.authorizationStatus == .restricted
        }
    }
}
