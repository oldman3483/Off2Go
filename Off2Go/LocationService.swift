//
//  LocationService.swift
//  Off2Go
//
//  Created by Heidie Lee on 2025/5/15.
//

import Foundation
import CoreLocation
import Combine
import UserNotifications

class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()
    
    private(set) var locationManager = CLLocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLocationEnabled: Bool = false
    
    // 地理圍欄
    @Published var monitoredRegions: [CLCircularRegion] = []
    
    // 權限請求狀態
    private var isRequestingPermission = false
    private var permissionCompletion: ((Bool) -> Void)?
    
    // 修復：快取系統狀態，避免重複查詢
    private var _cachedAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    private var _cachedLocationServicesEnabled: Bool = true // 預設為 true，透過委託更新
    private var _hasReceivedInitialCallback = false
    
    private override init() {
        super.init()
        setupLocationManager()
        // 修復：完全依賴委託回調，不做任何直接查詢
        _cachedAuthorizationStatus = .notDetermined
        authorizationStatus = .notDetermined
        _cachedLocationServicesEnabled = true
        updateLocationEnabledStatus()
        
        // 觸發初始權限檢查（這會調用委託）
        DispatchQueue.global(qos: .utility).async {
            DispatchQueue.main.async {
                // 這個調用會觸發 didChangeAuthorization 委託
                _ = self.locationManager.delegate
            }
        }
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        
        locationManager.pausesLocationUpdatesAutomatically = false
        
        if #available(iOS 6.0, *) {
            locationManager.activityType = .otherNavigation
        }
    }
    
    // MARK: - 修復權限相關方法
    
    /// 檢查位置權限是否足夠使用
    var hasLocationPermission: Bool {
        switch _cachedAuthorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }
    
    /// 檢查是否可以使用位置服務
    var canUseLocationService: Bool {
        // 修復：使用快取的狀態
        guard _cachedLocationServicesEnabled else {
            return false
        }
        return hasLocationPermission
    }
    
    /// 權限狀態字串描述
    var authorizationStatusString: String {
        return statusString(for: _cachedAuthorizationStatus)
    }
    
    func statusString(for status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "未決定"
        case .restricted: return "受限制"
        case .denied: return "已拒絕"
        case .authorizedAlways: return "總是允許"
        case .authorizedWhenInUse: return "使用時允許"
        @unknown default: return "未知狀態"
        }
    }
    
    func getCurrentAuthorizationStatus() -> CLAuthorizationStatus {
        return _cachedAuthorizationStatus
    }
    
    // MARK: - 修復後的權限請求方法
    
    func requestLocationPermission(completion: ((Bool) -> Void)? = nil) {
        print("🔐 [Location] 請求位置權限")
        
        guard !isRequestingPermission else {
            print("⚠️ [Location] 權限請求進行中，加入等待佇列...")
            if let newCompletion = completion {
                let existingCompletion = permissionCompletion
                permissionCompletion = { success in
                    existingCompletion?(success)
                    newCompletion(success)
                }
            }
            return
        }
        
        // 修復：移除直接查詢 locationServicesEnabled
        // 如果還沒收到初始回調，先等待
        guard _hasReceivedInitialCallback else {
            print("📍 [Location] 等待初始權限回調...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.requestLocationPermission(completion: completion)
            }
            return
        }
        
        // 檢查快取的系統狀態
        guard _cachedLocationServicesEnabled else {
            print("🚫 [Location] 系統位置服務未開啟（快取狀態）")
            completion?(false)
            return
        }
        
        let currentStatus = _cachedAuthorizationStatus
        print("📍 [Location] 當前權限狀態: \(statusString(for: currentStatus))")
        
        switch currentStatus {
        case .notDetermined:
            print("📍 [Location] 權限未決定，開始請求 WhenInUse 權限")
            isRequestingPermission = true
            permissionCompletion = completion
            
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async {
                    self.locationManager.requestWhenInUseAuthorization()
                }
            }
            
        case .authorizedWhenInUse:
            print("📍 [Location] 已有 WhenInUse 權限，請求升級到 Always")
            isRequestingPermission = true
            permissionCompletion = completion
            
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async {
                    self.locationManager.requestAlwaysAuthorization()
                }
            }
            
        case .denied, .restricted:
            print("🚫 [Location] 權限被拒絕或受限")
            completion?(false)
            
        case .authorizedAlways:
            print("✅ [Location] 已有 Always 權限")
            completion?(true)
            
        @unknown default:
            print("⚠️ [Location] 未知權限狀態，嘗試請求")
            isRequestingPermission = true
            permissionCompletion = completion
            
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async {
                    self.locationManager.requestWhenInUseAuthorization()
                }
            }
        }
    }
    
    // MARK: - 安全的狀態更新方法
    
    private func updateAuthorizationStatusSafely(_ newStatus: CLAuthorizationStatus) {
        _cachedAuthorizationStatus = newStatus
        _hasReceivedInitialCallback = true
        
        DispatchQueue.main.async {
            self.authorizationStatus = newStatus
            self.updateLocationEnabledStatus()
        }
    }
    
    func updateAuthorizationStatusSafely() {
        print("🔄 [Location] 狀態更新請求（等待委託回調）")
        // 不執行任何直接查詢
    }
    
    private func updateLocationEnabledStatus() {
        // 修復：使用快取的狀態
        let enabled = _cachedLocationServicesEnabled && hasLocationPermission
        
        if isLocationEnabled != enabled {
            isLocationEnabled = enabled
            
            print("🔍 [Location] 位置狀態更新:")
            print("   系統位置服務: \(_cachedLocationServicesEnabled ? "開啟" : "關閉") (快取)")
            print("   App權限狀態: \(authorizationStatusString)")
            print("   最終可用狀態: \(enabled ? "可用" : "不可用")")
        }
    }
    
    // MARK: - 位置更新控制
    
    func startUpdatingLocation() {
        let currentStatus = _cachedAuthorizationStatus
        
        guard currentStatus == .authorizedAlways || currentStatus == .authorizedWhenInUse else {
            print("🚫 [Location] 無法開始位置更新：權限不足")
            print("   當前權限: \(statusString(for: currentStatus))")
            return
        }
        
        guard _cachedLocationServicesEnabled else {
            print("🚫 [Location] 系統位置服務未開啟（快取狀態）")
            return
        }
        
        if currentStatus == .authorizedAlways {
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.main.async {
                    do {
                        self.locationManager.allowsBackgroundLocationUpdates = true
                        print("✅ [Location] 啟用背景位置更新")
                    } catch {
                        print("⚠️ [Location] 無法啟用背景位置更新: \(error.localizedDescription)")
                    }
                    self.locationManager.startUpdatingLocation()
                }
            }
        } else {
            print("📍 [Location] 開始位置更新")
            locationManager.startUpdatingLocation()
            locationManager.startMonitoringSignificantLocationChanges()
            print("📍 [Location] 啟動重要位置變化監控")
        }
    }
    
    func stopUpdatingLocation() {
        print("🛑 [Location] 停止位置更新")
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                if self.locationManager.allowsBackgroundLocationUpdates {
                    self.locationManager.allowsBackgroundLocationUpdates = false
                }
            }
        }
    }
    
    // MARK: - 地理圍欄
    
    func startMonitoringRegion(for stop: BusStop.Stop, radius: CLLocationDistance = 200) {
        guard canUseLocationService else {
            print("🚫 [Location] 無法設置地理圍欄：權限不足")
            return
        }
        
        if locationManager.monitoredRegions.contains(where: { $0.identifier == stop.StopID }) {
            print("⚠️ [Location] 已在監控此區域: \(stop.StopName.Zh_tw)")
            return
        }
        
        let region = CLCircularRegion(
            center: stop.StopPosition.coordinate,
            radius: radius,
            identifier: stop.StopID
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                self.locationManager.startMonitoring(for: region)
                self.monitoredRegions.append(region)
            }
        }
        
        print("📍 [Location] 開始監控區域: \(stop.StopName.Zh_tw) (半徑: \(radius)m)")
    }
    
    func stopMonitoringAllRegions() {
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                for region in self.locationManager.monitoredRegions {
                    self.locationManager.stopMonitoring(for: region)
                }
                self.monitoredRegions.removeAll()
            }
        }
        print("🛑 [Location] 已停止監控所有地理圍欄")
    }
    
    // MARK: - 實用方法
    
    func distanceTo(coordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let currentLocation = currentLocation else { return nil }
        
        let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return currentLocation.distance(from: targetLocation)
    }
    
    /// 檢查位置服務詳細狀態（使用快取）
    func checkLocationServiceStatus() -> (canUse: Bool, reason: String) {
        guard _cachedLocationServicesEnabled else {
            return (false, "系統位置服務已關閉，請到「設定 > 隱私權與安全性 > 定位服務」開啟")
        }
        
        switch _cachedAuthorizationStatus {
        case .notDetermined:
            return (false, "位置權限未決定，請允許應用程式使用位置服務")
        case .denied:
            return (false, "位置權限被拒絕，請到「設定 > Off2Go > 位置」開啟權限")
        case .restricted:
            return (false, "位置權限受到限制（可能是家長控制）")
        case .authorizedWhenInUse, .authorizedAlways:
            return (true, "位置權限正常")
        @unknown default:
            return (false, "未知的權限狀態")
        }
    }
    
    // 強制檢查系統位置服務狀態（在背景執行）
    func forceCheckLocationServicesStatus(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let enabled = CLLocationManager.locationServicesEnabled()
            DispatchQueue.main.async {
                self._cachedLocationServicesEnabled = enabled
                self.updateLocationEnabledStatus()
                completion(enabled)
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            self.currentLocation = location
        }
        
        #if DEBUG
        print("📍 [Location] 位置更新: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        #endif
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ [Location] 位置更新失敗: \(error.localizedDescription)")
        
        if let clError = error as? CLError {
            switch clError.code {
            case .locationUnknown:
                print("   位置暫時無法取得，會繼續嘗試")
            case .denied:
                print("   位置權限被拒絕")
                updateAuthorizationStatusSafely(.denied)
            case .network:
                print("   網路錯誤，可能影響位置精度")
            default:
                print("   其他位置錯誤: \(clError.localizedDescription)")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("🔄 [Location] Delegate 權限狀態變更: \(statusString(for: _cachedAuthorizationStatus)) -> \(statusString(for: status))")
        
        // 同時更新系統位置服務狀態（在背景執行）
        DispatchQueue.global(qos: .utility).async {
            let servicesEnabled = CLLocationManager.locationServicesEnabled()
            DispatchQueue.main.async {
                self._cachedLocationServicesEnabled = servicesEnabled
                print("🔄 [Location] 系統位置服務狀態: \(servicesEnabled)")
            }
        }
        
        updateAuthorizationStatusSafely(status)
        
        // 處理權限請求回調
        if isRequestingPermission {
            isRequestingPermission = false
            
            let success = status == .authorizedWhenInUse || status == .authorizedAlways
            permissionCompletion?(success)
            permissionCompletion = nil
            
            print("🔐 [Location] 權限請求結果: \(success ? "成功" : "失敗")")
        }
        
        // 根據權限狀態自動控制位置更新
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            if locationManager.monitoredRegions.isEmpty {
                startUpdatingLocation()
            }
        case .denied, .restricted:
            stopUpdatingLocation()
            stopMonitoringAllRegions()
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("📍 [Location] 進入區域: \(region.identifier)")
        
        let content = UNMutableNotificationContent()
        content.title = "接近公車站"
        content.body = "您已接近目標站點"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "location-\(region.identifier)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ [Location] 發送通知失敗: \(error.localizedDescription)")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("📍 [Location] 離開區域: \(region.identifier)")
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("❌ [Location] 地理圍欄監控失敗: \(error.localizedDescription)")
        
        if let region = region {
            print("   失敗的區域: \(region.identifier)")
        }
    }
}
