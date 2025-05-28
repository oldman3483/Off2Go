//
//  LocationService.swift
//  BusNotify
//
//  Created by Heidie Lee on 2025/5/15.
//

import Foundation
import CoreLocation
import Combine
import UserNotifications

class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()
    
    private let locationManager = CLLocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLocationEnabled: Bool = false
    
    // 地理圍欄
    @Published var monitoredRegions: [CLCircularRegion] = []
    
    // 權限請求狀態
    private var isRequestingPermission = false
    private var permissionCompletion: ((Bool) -> Void)?
    
    private override init() {
        super.init()
        setupLocationManager()
        updateAuthorizationStatus()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // 更新位置的最小距離（米）
        
        // 只有在需要背景位置時才設定背景更新
        // locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        
        // 初始化時更新權限狀態
        authorizationStatus = locationManager.authorizationStatus
        updateLocationEnabledStatus()
    }
    
    // MARK: - 權限相關方法
    
    /// 檢查位置權限是否足夠使用
    var hasLocationPermission: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }
    
    /// 檢查是否可以使用位置服務
    var canUseLocationService: Bool {
        guard CLLocationManager.locationServicesEnabled() else {
            print("🚫 [Location] 位置服務已在系統設定中關閉")
            return false
        }
        
        return hasLocationPermission
    }
    
    /// 更新位置啟用狀態
    private func updateLocationEnabledStatus() {
        let enabled = CLLocationManager.locationServicesEnabled() && hasLocationPermission
        
        DispatchQueue.main.async {
            self.isLocationEnabled = enabled
        }
        
        print("🔍 [Location] 位置狀態更新:")
        print("   系統位置服務: \(CLLocationManager.locationServicesEnabled() ? "開啟" : "關閉")")
        print("   App權限狀態: \(authorizationStatusString)")
        print("   最終可用狀態: \(enabled ? "可用" : "不可用")")
    }
    
    /// 權限狀態字串描述
    var authorizationStatusString: String {
        switch authorizationStatus {
        case .notDetermined:
            return "未決定"
        case .restricted:
            return "受限制"
        case .denied:
            return "已拒絕"
        case .authorizedAlways:
            return "總是允許"
        case .authorizedWhenInUse:
            return "使用時允許"
        @unknown default:
            return "未知狀態"
        }
    }
    
    // MARK: - 權限請求
    
    func requestLocationPermission(completion: ((Bool) -> Void)? = nil) {
        guard !isRequestingPermission else {
            print("⚠️ [Location] 已在請求權限中，跳過重複請求")
            completion?(false)
            return
        }
        
        print("🔐 [Location] 開始請求位置權限，當前狀態: \(authorizationStatusString)")
        
        // 檢查系統位置服務是否開啟
        guard CLLocationManager.locationServicesEnabled() else {
            print("🚫 [Location] 系統位置服務未開啟")
            completion?(false)
            return
        }
        
        isRequestingPermission = true
        permissionCompletion = completion
        
        switch authorizationStatus {
        case .notDetermined:
            // 首次請求，先請求 WhenInUse 權限
            print("📍 [Location] 請求 WhenInUse 權限")
            locationManager.requestWhenInUseAuthorization()
            
        case .denied, .restricted:
            print("🚫 [Location] 權限被拒絕或受限，需要用戶手動開啟")
            isRequestingPermission = false
            completion?(false)
            
        case .authorizedWhenInUse:
            // 如果需要背景位置，可以請求 Always 權限
            // 但通常 WhenInUse 就足夠了
            print("✅ [Location] 已有 WhenInUse 權限")
            isRequestingPermission = false
            completion?(true)
            
        case .authorizedAlways:
            print("✅ [Location] 已有 Always 權限")
            isRequestingPermission = false
            completion?(true)
            
        @unknown default:
            print("⚠️ [Location] 未知權限狀態")
            isRequestingPermission = false
            completion?(false)
        }
    }
    
    /// 請求背景位置權限（在有 WhenInUse 權限的基礎上）
    func requestAlwaysAuthorization() {
        guard authorizationStatus == .authorizedWhenInUse else {
            print("⚠️ [Location] 需要先有 WhenInUse 權限才能請求 Always 權限")
            return
        }
        
        print("🔐 [Location] 請求 Always 權限")
        locationManager.requestAlwaysAuthorization()
    }
    
    // MARK: - 位置更新控制
    
    func startUpdatingLocation() {
        guard canUseLocationService else {
            print("🚫 [Location] 無法開始位置更新：權限不足或服務未開啟")
            return
        }
        
        print("📍 [Location] 開始位置更新")
        locationManager.startUpdatingLocation()
    }
    
    func stopUpdatingLocation() {
        print("🛑 [Location] 停止位置更新")
        locationManager.stopUpdatingLocation()
    }
    
    // MARK: - 地理圍欄
    
    func startMonitoringRegion(for stop: BusStop.Stop, radius: CLLocationDistance = 200) {
        guard canUseLocationService else {
            print("🚫 [Location] 無法設置地理圍欄：權限不足")
            return
        }
        
        // 檢查是否已經在監控這個區域
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
        
        locationManager.startMonitoring(for: region)
        monitoredRegions.append(region)
        
        print("📍 [Location] 開始監控區域: \(stop.StopName.Zh_tw) (半徑: \(radius)m)")
    }
    
    func stopMonitoringAllRegions() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        monitoredRegions.removeAll()
        print("🛑 [Location] 已停止監控所有地理圍欄")
    }
    
    // MARK: - 實用方法
    
    /// 計算到指定座標的距離
    func distanceTo(coordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let currentLocation = currentLocation else { return nil }
        
        let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return currentLocation.distance(from: targetLocation)
    }
    
    /// 檢查位置服務的詳細狀態
    func checkLocationServiceStatus() -> (canUse: Bool, reason: String) {
        // 檢查系統位置服務
        guard CLLocationManager.locationServicesEnabled() else {
            return (false, "系統位置服務已關閉，請到「設定 > 隱私權與安全性 > 定位服務」開啟")
        }
        
        // 檢查App權限
        switch authorizationStatus {
        case .notDetermined:
            return (false, "尚未請求位置權限")
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
    
    /// 更新權限狀態（供外部調用）
    func updateAuthorizationStatus() {
        let newStatus = locationManager.authorizationStatus
        
        DispatchQueue.main.async {
            if self.authorizationStatus != newStatus {
                print("🔄 [Location] 權限狀態變更: \(self.authorizationStatusString) -> \(self.statusString(for: newStatus))")
                self.authorizationStatus = newStatus
                self.updateLocationEnabledStatus()
            }
        }
    }
    
    private func statusString(for status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "未決定"
        case .restricted: return "受限制"
        case .denied: return "已拒絕"
        case .authorizedAlways: return "總是允許"
        case .authorizedWhenInUse: return "使用時允許"
        @unknown default: return "未知狀態"
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
        
        // 只在調試時輸出位置更新
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
                DispatchQueue.main.async {
                    self.authorizationStatus = .denied
                    self.updateLocationEnabledStatus()
                }
            default:
                print("   其他位置錯誤: \(clError.localizedDescription)")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("🔄 [Location] 權限狀態變更: \(authorizationStatusString) -> \(statusString(for: status))")
        
        DispatchQueue.main.async {
            self.authorizationStatus = status
            self.updateLocationEnabledStatus()
        }
        
        // 處理權限請求的回調
        if isRequestingPermission {
            isRequestingPermission = false
            
            let success = status == .authorizedWhenInUse || status == .authorizedAlways
            permissionCompletion?(success)
            permissionCompletion = nil
            
            print("🔐 [Location] 權限請求結果: \(success ? "成功" : "失敗")")
        }
        
        // 根據新的權限狀態自動開始或停止位置更新
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            startUpdatingLocation()
        case .denied, .restricted:
            stopUpdatingLocation()
            stopMonitoringAllRegions()
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("📍 [Location] 進入區域: \(region.identifier)")
        
        // 發送本地通知
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
