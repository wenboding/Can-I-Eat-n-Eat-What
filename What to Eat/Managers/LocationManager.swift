import Combine
import CoreLocation
import Foundation
import MapKit

enum LocationManagerError: LocalizedError {
    case servicesDisabled
    case permissionDenied
    case timeout
    case noLocation

    var errorDescription: String? {
        switch self {
        case .servicesDisabled:
            return AppLanguage.current == .simplifiedChinese ? "此设备已关闭定位服务。" : "Location services are disabled on this device."
        case .permissionDenied:
            return AppLanguage.current == .simplifiedChinese ? "定位权限被拒绝。你仍可在不使用附近餐厅推荐的情况下继续。" : "Location permission is denied. You can continue without nearby restaurants."
        case .timeout:
            return AppLanguage.current == .simplifiedChinese ? "未能在限定时间内获取定位。" : "Unable to get location in time."
        case .noLocation:
            return AppLanguage.current == .simplifiedChinese ? "无法确定你的位置。" : "Unable to determine your location."
        }
    }
}

struct NearbyRestaurant: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let distanceMiles: Double
    let category: String
}

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager: CLLocationManager
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus

        super.init()

        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    deinit {
        timeoutTask?.cancel()
    }

    func requestWhenInUsePermission() {
        manager.requestWhenInUseAuthorization()
    }

    func requestCurrentCoordinate() async throws -> CLLocationCoordinate2D {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationManagerError.servicesDisabled
        }

        if authorizationStatus == .notDetermined {
            try await requestAuthorizationIfNeeded()
        }

        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            throw LocationManagerError.permissionDenied
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocationCoordinate2D, Error>) in
            locationContinuation = continuation
            manager.requestLocation()

            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard let self else { return }
                if let continuation = self.locationContinuation {
                    self.locationContinuation = nil
                    continuation.resume(throwing: LocationManagerError.timeout)
                }
            }
        }
    }

    func nearbyRestaurants(radiusMiles: Double, maxResults: Int = 5) async throws -> [NearbyRestaurant] {
        let coordinate = try await requestCurrentCoordinate()

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "restaurant"

        let meters = max(radiusMiles, 0.5) * 1609.34
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: meters * 2,
            longitudinalMeters: meters * 2
        )

        let response = try await MKLocalSearch(request: request).start()

        let centerLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        let mapped = response.mapItems.compactMap { mapItem -> NearbyRestaurant? in
            guard let name = mapItem.name else { return nil }
            guard let location = mapItem.placemark.location else { return nil }

            let distanceMiles = centerLocation.distance(from: location) / 1609.34
            let category = mapItem.pointOfInterestCategory?
                .rawValue
                .replacingOccurrences(of: "_", with: " ")
                .capitalized ?? "Restaurant"

            return NearbyRestaurant(
                name: name,
                distanceMiles: distanceMiles,
                category: category
            )
        }

        return Array(mapped.sorted(by: { $0.distanceMiles < $1.distanceMiles }).prefix(maxResults))
    }

    private func requestAuthorizationIfNeeded() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            authorizationStatus = manager.authorizationStatus

            guard let continuation = authorizationContinuation else { return }
            authorizationContinuation = nil

            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                continuation.resume()
            case .denied, .restricted:
                continuation.resume(throwing: LocationManagerError.permissionDenied)
            case .notDetermined:
                break
            @unknown default:
                continuation.resume(throwing: LocationManagerError.permissionDenied)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let continuation = locationContinuation else { return }

            timeoutTask?.cancel()
            timeoutTask = nil
            locationContinuation = nil

            if let coordinate = locations.last?.coordinate {
                continuation.resume(returning: coordinate)
            } else {
                continuation.resume(throwing: LocationManagerError.noLocation)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let continuation = locationContinuation else { return }

            timeoutTask?.cancel()
            timeoutTask = nil
            locationContinuation = nil

            continuation.resume(throwing: error)
        }
    }
}
