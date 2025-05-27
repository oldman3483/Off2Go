//
//  StationMonitoringService.swift
//  BusNotify
//
//  Created by Heidie Lee on 2025/5/15.
//

import Foundation
import Combine
import CoreLocation
import UserNotifications

class StationMonitoringService: ObservableObject {
    private let tdxService = TDXService.shared
    private let locationService = LocationService.shared
    private let notificationService = NotificationService.shared
    
    @Published var selectedRoute: BusRoute?
    @Published var selectedDirection: Int = 0
    @Published var stops: [BusStop.Stop] = []
    @Published var arrivals: [String: BusArrival] = [:]  // StopID -> BusArrival
    @Published var isMonitoring: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // 監控狀態
    @Published var nearestStopIndex: Int?
    @Published var monitoringStartTime: Date?
    @Published var notifiedStops: Set<String> = []
    
    private var cancellables = Set<AnyCancellable>()
    private var arrivalTimer: Timer?
    private var lastUserLocation: CLLocation?
    
    // 設定值
    private var notifyDistance: Double {
        UserDefaults.standard.double(forKey: "notifyDistance") == 0 ? 200 : UserDefaults.standard.double(forKey: "notifyDistance")
    }
    
    private var autoStopMonitoring: Bool {
        UserDefaults.standard.bool(forKey: "autoStopMonitoring")
    }
    
    private var voiceAnnouncement: Bool {
        UserDefaults.standard.bool(forKey: "voiceAnnouncement")
    }
    
    init() {
        setupLocationMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // 設置位置監控
    private func setupLocationMonitoring() {
        // 監聽位置變化
        locationService.$currentLocation
            .compactMap { $0 }
            .removeDuplicates { old, new in
                // 過濾掉距離變化小於10米的位置更新
                old.distance(from: new) < 10
            }
            .sink { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
        
        // 監聽位置權限變化
        locationService.$authorizationStatus
            .sink { [weak self] status in
                self?.handleLocationAuthorizationChange(status)
            }
            .store(in: &cancellables)
    }
    
    // 設置路線和方向
    func setRoute(_ route: BusRoute, direction: Int) {
        selectedRoute = route
        selectedDirection = direction
        
        // 重置狀態
        stops.removeAll()
        arrivals.removeAll()
        errorMessage = nil
        notifiedStops.removeAll()
        nearestStopIndex = nil
        
        // 獲取站點
        fetchStops()
    }
    
    // 獲取站點資料
    private func fetchStops() {
        guard let route = selectedRoute else { return }
        
        isLoading = true
        errorMessage = nil
        
        tdxService.getStops(city: "Taipei", routeName: route.RouteID) { [weak self] busStops, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "獲取站點失敗: \(error.localizedDescription)"
                    return
                }
                
                guard let stopsData = busStops,
                      let busStop = stopsData.first(where: { $0.RouteID == route.RouteID }) else {
                    self.errorMessage = "找不到路線站點資料"
                    return
                }
                
                // 根據選擇的方向過濾站點
                self.stops = busStop.Stops.filter { $0.StopSequence == self.selectedDirection }
                    .sorted { $0.StopSequence < $1.StopSequence }
                
                if self.stops.isEmpty {
                    self.errorMessage = "該方向暫無站點資料"
                } else {
                    // 獲取實時到站資訊
                    self.updateEstimatedArrivalTimes()
                    
                    // 如果正在監控，更新地理圍欄
                    if self.isMonitoring {
                        self.setupGeofencing()
                    }
                }
            }
        }
    }
    
    // 開始監控
    func startMonitoring() {
        guard !stops.isEmpty, let route = selectedRoute else {
            errorMessage = "無法開始監控：沒有站點資料"
            return
        }
        
        // 檢查位置權限
        guard locationService.authorizationStatus == .authorizedAlways ||
              locationService.authorizationStatus == .authorizedWhenInUse else {
            errorMessage = "需要位置權限才能開始監控"
            return
        }
        
        isMonitoring = true
        monitoringStartTime = Date()
        notifiedStops.removeAll()
        errorMessage = nil
        
        // 開始位置更新
        locationService.startUpdatingLocation()
        
        // 設置地理圍欄
        setupGeofencing()
        
        // 設置定時刷新實時到站資訊 (每30秒)
        arrivalTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateEstimatedArrivalTimes()
        }
        
        // 立即更新一次到站資訊
        updateEstimatedArrivalTimes()
        
        // 發送開始監控通知
        notificationService.sendNotification(
            title: "開始監控",
            body: "正在監控路線 \(route.RouteName.Zh_tw) (\(selectedDirection == 0 ? "去程" : "回程"))"
        )
        
        print("開始監控路線: \(route.RouteName.Zh_tw), 方向: \(selectedDirection == 0 ? "去程" : "回程"), 站點數: \(stops.count)")
    }
    
    // 停止監控
    func stopMonitoring() {
        isMonitoring = false
        monitoringStartTime = nil
        notifiedStops.removeAll()
        
        // 停止定時器
        arrivalTimer?.invalidate()
        arrivalTimer = nil
        
        // 停止位置更新
        locationService.stopUpdatingLocation()
        
        // 移除所有地理圍欄
        locationService.stopMonitoringAllRegions()
        
        // 發送停止監控通知
        if let route = selectedRoute {
            notificationService.sendNotification(
                title: "停止監控",
                body: "已停止監控路線 \(route.RouteName.Zh_tw)"
            )
        }
        
        print("已停止監控")
    }
    
    // 設置地理圍欄
    private func setupGeofencing() {
        guard isMonitoring else { return }
        
        // 移除舊的地理圍欄
        locationService.stopMonitoringAllRegions()
        
        // 為每個站點設置地理圍欄
        for stop in stops {
            locationService.startMonitoringRegion(for: stop, radius: notifyDistance)
        }
        
        print("已設置 \(stops.count) 個地理圍欄，半徑: \(notifyDistance) 米")
    }
    
    // 更新實時到站資訊
    private func updateEstimatedArrivalTimes() {
        guard let route = selectedRoute else { return }
        
        tdxService.getEstimatedTimeOfArrival(city: "Taipei", routeName: route.RouteID) { [weak self] arrivals, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    print("更新到站資訊失敗: \(error.localizedDescription)")
                    return
                }
                
                guard let arrivals = arrivals else { return }
                
                // 篩選對應方向的到站資訊
                let filteredArrivals = arrivals.filter { $0.Direction == self.selectedDirection }
                
                // 更新到站資訊字典
                var newArrivals: [String: BusArrival] = [:]
                for arrival in filteredArrivals {
                    newArrivals[arrival.StopID] = arrival
                }
                
                self.arrivals = newArrivals
                print("已更新 \(newArrivals.count) 個站點的到站資訊")
            }
        }
    }
    
    // 處理位置更新
    private func handleLocationUpdate(_ location: CLLocation) {
        lastUserLocation = location
        
        guard isMonitoring else { return }
        
        // 更新最近站點
        updateNearestStop(userLocation: location)
        
        // 檢查是否需要通知
        checkForStationNotifications(userLocation: location)
    }
    
    // 處理位置權限變化
    private func handleLocationAuthorizationChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .denied, .restricted:
            if isMonitoring {
                stopMonitoring()
                errorMessage = "位置權限被拒絕，已停止監控"
            }
        case .authorizedAlways, .authorizedWhenInUse:
            errorMessage = nil
        default:
            break
        }
    }
    
    // 更新最近站點
    private func updateNearestStop(userLocation: CLLocation) {
        guard !stops.isEmpty else { return }
        
        var minDistance = Double.infinity
        var minIndex: Int?
        
        for (index, stop) in stops.enumerated() {
            let stopLocation = CLLocation(
                latitude: stop.StopPosition.PositionLat,
                longitude: stop.StopPosition.PositionLon
            )
            
            let distance = userLocation.distance(from: stopLocation)
            if distance < minDistance {
                minDistance = distance
                minIndex = index
            }
        }
        
        nearestStopIndex = minIndex
    }
    
    // 檢查站點通知
    private func checkForStationNotifications(userLocation: CLLocation) {
        for stop in stops {
            // 跳過已經通知過的站點
            if notifiedStops.contains(stop.StopID) {
                continue
            }
            
            let stopLocation = CLLocation(
                latitude: stop.StopPosition.PositionLat,
                longitude: stop.StopPosition.PositionLon
            )
            
            let distance = userLocation.distance(from: stopLocation)
            
            // 如果距離小於設定的通知距離
            if distance <= notifyDistance {
                // 標記為已通知
                notifiedStops.insert(stop.StopID)
                
                // 獲取到站資訊
                let arrival = arrivals[stop.StopID]
                let estimatedTimeText = arrival?.arrivalTimeText ?? "無到站資訊"
                
                // 發送通知
                let title = "接近站點: \(stop.StopName.Zh_tw)"
                let body = "距離: \(Int(distance))公尺\n公車到站: \(estimatedTimeText)"
                
                notificationService.sendNotification(title: title, body: body)
                
                // 語音播報
                if voiceAnnouncement {
                    notificationService.announceStation(
                        stopName: stop.StopName.Zh_tw,
                        estimatedTime: estimatedTimeText
                    )
                }
                
                print("通知站點: \(stop.StopName.Zh_tw), 距離: \(Int(distance))m, 到站時間: \(estimatedTimeText)")
                
                // 檢查是否為終點站，如果是且開啟自動停止，則停止監控
                if autoStopMonitoring && isLastStop(stop) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.stopMonitoring()
                    }
                }
            }
        }
    }
    
    // 檢查是否為終點站
    private func isLastStop(_ stop: BusStop.Stop) -> Bool {
        guard let lastStop = stops.last else { return false }
        return stop.StopID == lastStop.StopID
    }
    
    // 計算到特定站點的距離
    func distanceToStop(_ stop: BusStop.Stop) -> Double {
        guard let userLocation = lastUserLocation else {
            return Double.infinity
        }
        
        let stopLocation = CLLocation(
            latitude: stop.StopPosition.PositionLat,
            longitude: stop.StopPosition.PositionLon
        )
        
        return userLocation.distance(from: stopLocation)
    }
    
    // 獲取監控統計資訊
    func getMonitoringStats() -> (duration: TimeInterval, notifiedCount: Int, totalStops: Int) {
        let duration = monitoringStartTime?.timeIntervalSinceNow.magnitude ?? 0
        return (duration, notifiedStops.count, stops.count)
    }
    
    // 手動刷新資料
    func refreshData() {
        guard let route = selectedRoute else { return }
        
        // 重新獲取站點和到站資訊
        fetchStops()
        
        // 如果正在監控，更新地理圍欄
        if isMonitoring {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.setupGeofencing()
            }
        }
    }
    
    // 重置通知狀態
    func resetNotificationStatus() {
        notifiedStops.removeAll()
        print("已重置通知狀態")
    }
    
    // 獲取特定站點的詳細資訊
    func getStopInfo(_ stopID: String) -> (stop: BusStop.Stop?, arrival: BusArrival?, distance: Double) {
        let stop = stops.first { $0.StopID == stopID }
        let arrival = arrivals[stopID]
        let distance = stop != nil ? distanceToStop(stop!) : Double.infinity
        
        return (stop, arrival, distance)
    }
    
    // 檢查監控狀態是否健康
    func checkMonitoringHealth() -> (isHealthy: Bool, issues: [String]) {
        var issues: [String] = []
        
        // 檢查位置權限
        let locationStatus = locationService.authorizationStatus
        if locationStatus != .authorizedAlways && locationStatus != .authorizedWhenInUse {
            issues.append("位置權限未授權")
        }
        
        // 檢查是否有站點資料
        if stops.isEmpty {
            issues.append("無站點資料")
        }
        
        // 檢查定時器是否運行
        if isMonitoring && arrivalTimer == nil {
            issues.append("到站資訊更新定時器未運行")
        }
        
        // 檢查位置更新
        if isMonitoring && lastUserLocation == nil {
            issues.append("無法獲取位置資訊")
        }
        
        // 檢查 API 連線
        if let errorMessage = tdxService.errorMessage {
            issues.append("API 連線問題: \(errorMessage)")
        }
        
        return (issues.isEmpty, issues)
    }
    
    // 強制停止監控（用於錯誤恢復）
    func forceStopMonitoring() {
        isMonitoring = false
        monitoringStartTime = nil
        notifiedStops.removeAll()
        errorMessage = nil
        
        arrivalTimer?.invalidate()
        arrivalTimer = nil
        
        locationService.stopUpdatingLocation()
        locationService.stopMonitoringAllRegions()
        
        print("已強制停止監控")
    }
}
