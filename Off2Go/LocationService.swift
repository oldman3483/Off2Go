//
//  LocationService.swift
//  BusNotify
//
//  Created by Heidie Lee on 2025/5/15.
//

import Foundation
import CoreLocation
import Combine

class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()
    
    private let locationManager = CLLocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    // 地理圍欄
    @Published var monitoredRegions: [CLCircularRegion] = []
    
    private override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // 更新位置的最小距離（米）
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }
    
    func requestLocationPermission() {
        locationManager.requestAlwaysAuthorization()
    }
    
    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }
    
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
    
    func startMonitoringRegion(for stop: BusStop.Stop, radius: CLLocationDistance = 200) {
        let region = CLCircularRegion(
            center: stop.StopPosition.coordinate,
            radius: radius,
            identifier: stop.StopID
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false
        
        if !locationManager.monitoredRegions.contains(where: { $0.identifier == stop.StopID }) {
            locationManager.startMonitoring(for: region)
            monitoredRegions.append(region)
        }
    }
    
    func stopMonitoringAllRegions() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        monitoredRegions.removeAll()
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("位置更新失敗: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            startUpdatingLocation()
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("進入區域: \(region.identifier)")
        NotificationService.shared.sendNotification(
            title: "接近公車站",
            body: "您已接近站點 \(region.identifier)"
        )
    }
}
