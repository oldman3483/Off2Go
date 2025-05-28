//
//  StationMonitoringService.swift
//  Off2Go
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
    private let audioService = AudioNotificationService.shared
    
    @Published var selectedRoute: BusRoute?
    @Published var selectedDirection: Int = 0
    @Published var stops: [BusStop.Stop] = []
    @Published var arrivals: [String: BusArrival] = [:]
    @Published var isMonitoring: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // 音頻相關狀態
    @Published var destinationStopName: String?
    @Published var isAudioMonitoringEnabled: Bool = false
    @Published var notificationStopsAhead: Int = 2
    
    // 監控狀態
    @Published var nearestStopIndex: Int?
    @Published var monitoringStartTime: Date?
    @Published var notifiedStops: Set<String> = []
    @Published var destinationStopIndex: Int?
    
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
    
    init() {
        setupLocationMonitoring()
        setupAudioServiceIntegration()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - 音頻服務整合
    
    private func setupAudioServiceIntegration() {
        // 監聽音頻服務狀態變化
        audioService.$isAudioEnabled
            .sink { [weak self] isEnabled in
                self?.isAudioMonitoringEnabled = isEnabled
            }
            .store(in: &cancellables)
        
        audioService.$notificationDistance
            .sink { [weak self] distance in
                self?.notificationStopsAhead = distance
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 位置監控設定
    
    private func setupLocationMonitoring() {
        locationService.$currentLocation
            .compactMap { $0 }
            .removeDuplicates { old, new in
                old.distance(from: new) < 10
            }
            .sink { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
        
        locationService.$authorizationStatus
            .sink { [weak self] status in
                self?.handleLocationAuthorizationChange(status)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 路線設定與目的地
    
    func setRoute(_ route: BusRoute, direction: Int) {
        print("🚌 [Monitor] 設定路線: \(route.RouteName.Zh_tw) (方向: \(direction))")
        
        selectedRoute = route
        selectedDirection = direction
        
        // 重置狀態
        stops.removeAll()
        arrivals.removeAll()
        errorMessage = nil
        notifiedStops.removeAll()
        nearestStopIndex = nil
        destinationStopIndex = nil
        
        // 清除音頻服務的目的地
        audioService.clearDestination()
        
        fetchStops()
    }
    
    func setDestinationStop(_ stopName: String) {
        destinationStopName = stopName
        
        // 在站點列表中查找目的地索引
        if let index = stops.firstIndex(where: { $0.StopName.Zh_tw.contains(stopName) }) {
            destinationStopIndex = index
        }
        
        // 設定音頻服務的目的地
        if let route = selectedRoute {
            audioService.setDestination(route.RouteName.Zh_tw, stopName: stopName)
        }
        
        print("🎯 [Monitor] 已設定目的地站點: \(stopName)")
    }
    
    func clearDestinationStop() {
        destinationStopName = nil
        destinationStopIndex = nil
        audioService.clearDestination()
        print("🗑️ [Monitor] 已清除目的地站點")
    }
    
    // MARK: - 獲取站點資料 - 修復版本
    
    private func fetchStops() {
        guard let route = selectedRoute else {
            print("❌ [Monitor] 沒有選擇的路線")
            errorMessage = "沒有選擇路線"
            return
        }
        
        print("🔄 [Monitor] 開始獲取路線站點:")
        print("   路線名稱: \(route.RouteName.Zh_tw)")
        print("   路線ID: \(route.RouteID)")
        print("   方向: \(selectedDirection)")
        
        isLoading = true
        errorMessage = nil
        stops.removeAll()
        
        let city = determineCityFromCurrentLocation()
        print("   使用城市: \(city)")
        
        // 首先測試路線是否存在
        tdxService.testRouteAvailability(city: city, routeName: route.RouteID) { [weak self] exists, message in
            guard let self = self else { return }
            
            print("🔍 [Monitor] 路線可用性測試: \(exists ? "✅" : "❌") - \(message)")
            
            if !exists {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "路線不存在: \(message)"
                }
                return
            }
            
            // 路線存在，繼續獲取站點
            self.tdxService.getStops(city: city, routeName: route.RouteID) { [weak self] busStops, error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        let errorMsg = "獲取站點失敗: \(error.localizedDescription)"
                        self.errorMessage = errorMsg
                        print("❌ [Monitor] \(errorMsg)")
                        return
                    }
                    
                    guard let stopsData = busStops, !stopsData.isEmpty else {
                        let errorMsg = "API回傳空數據或無站點資料"
                        self.errorMessage = errorMsg
                        print("❌ [Monitor] \(errorMsg)")
                        return
                    }
                    
                    print("📍 [Monitor] API回傳 \(stopsData.count) 個路線的站點數據")
                    
                    // 改進的路線匹配邏輯
                    let matchedBusStop = self.findMatchingRoute(stopsData, targetRoute: route)
                    
                    guard let busStop = matchedBusStop else {
                        let availableRoutes = stopsData.map { $0.RouteID }.joined(separator: ", ")
                        let errorMsg = "找不到匹配的路線資料\n目標: \(route.RouteID)\n可用: \(availableRoutes)"
                        self.errorMessage = errorMsg
                        print("❌ [Monitor] \(errorMsg)")
                        return
                    }
                    
                    print("✅ [Monitor] 找到匹配的路線: \(busStop.RouteID)")
                    print("   原始站點數: \(busStop.Stops.count)")
                    
                    // 根據方向過濾站點
                    let filteredStops = self.filterStopsByDirection(busStop.Stops, direction: self.selectedDirection)
                    
                    if filteredStops.isEmpty {
                        self.errorMessage = "該方向暫無站點資料"
                        print("⚠️ [Monitor] 過濾後站點數為 0")
                    } else {
                        self.stops = filteredStops
                        print("✅ [Monitor] 成功載入 \(filteredStops.count) 個站點")
                        
                        // 立即更新到站時間
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.updateEstimatedArrivalTimes()
                        }
                        
                        if self.isMonitoring {
                            self.setupGeofencing()
                        }
                        
                        // 輸出前幾個站點供除錯
                        for (index, stop) in filteredStops.prefix(3).enumerated() {
                            print("   站點\(index+1): \(stop.StopName.Zh_tw) (序號: \(stop.StopSequence))")
                        }
                    }
                }
            }
        }
    }
    
    // 改進的路線匹配方法
    private func findMatchingRoute(_ stopsData: [BusStop], targetRoute: BusRoute) -> BusStop? {
        // 1. 首先嘗試完全匹配 RouteID
        if let exactMatch = stopsData.first(where: { $0.RouteID == targetRoute.RouteID }) {
            print("🎯 [Monitor] 找到完全匹配的RouteID: \(exactMatch.RouteID)")
            return exactMatch
        }
        
        // 2. 嘗試匹配路線名稱
        if let nameMatch = stopsData.first(where: { busStop in
            busStop.RouteID.contains(targetRoute.RouteName.Zh_tw) ||
            targetRoute.RouteName.Zh_tw.contains(busStop.RouteID)
        }) {
            print("🎯 [Monitor] 找到名稱匹配的路線: \(nameMatch.RouteID)")
            return nameMatch
        }
        
        // 3. 如果只有一個結果，直接使用
        if stopsData.count == 1 {
            print("🎯 [Monitor] 只有一個結果，直接使用: \(stopsData[0].RouteID)")
            return stopsData[0]
        }
        
        print("❌ [Monitor] 無法找到匹配的路線")
        return nil
    }
    
    // 根據方向過濾站點
    private func filterStopsByDirection(_ stops: [BusStop.Stop], direction: Int) -> [BusStop.Stop] {
        // 根據站點序號排序
        let sortedStops = stops.sorted { $0.StopSequence < $1.StopSequence }
        
        // 如果有方向相關的邏輯，可以在這裡實現
        // 目前先返回所有站點
        return sortedStops
    }
    
    // 改進的城市判斷方法
    private func determineCityFromCurrentLocation() -> String {
        // 1. 先檢查使用者設定
        if let savedCity = UserDefaults.standard.string(forKey: "selectedCity"), !savedCity.isEmpty {
            print("🏙️ [Monitor] 使用儲存的城市: \(savedCity)")
            return savedCity
        }
        
        // 2. 根據位置判斷
        guard let location = locationService.currentLocation else {
            print("🏙️ [Monitor] 無位置資訊，使用預設: Taipei")
            return "Taipei"
        }
        
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        print("🗺️ [Monitor] 當前座標: \(lat), \(lon)")
        
        // 台北市
        if lat >= 25.0 && lat <= 25.2 && lon >= 121.4 && lon <= 121.7 {
            print("🏙️ [Monitor] 判斷為台北市")
            return "Taipei"
        }
        
        // 新北市
        if lat >= 24.8 && lat <= 25.3 && lon >= 121.2 && lon <= 122.0 {
            print("🏙️ [Monitor] 判斷為新北市")
            return "NewTaipei"
        }
        
        // 桃園市
        if lat >= 24.8 && lat <= 25.1 && lon >= 121.1 && lon <= 121.5 {
            print("🏙️ [Monitor] 判斷為桃園市")
            return "Taoyuan"
        }
        
        // 台中市
        if lat >= 24.0 && lat <= 24.3 && lon >= 120.5 && lon <= 121.0 {
            print("🏙️ [Monitor] 判斷為台中市")
            return "Taichung"
        }
        
        // 台南市
        if lat >= 22.9 && lat <= 23.2 && lon >= 120.1 && lon <= 120.4 {
            print("🏙️ [Monitor] 判斷為台南市")
            return "Tainan"
        }
        
        // 高雄市
        if lat >= 22.5 && lat <= 22.8 && lon >= 120.2 && lon <= 120.5 {
            print("🏙️ [Monitor] 判斷為高雄市")
            return "Kaohsiung"
        }
        
        print("🏙️ [Monitor] 無法判斷城市，使用預設: Taipei")
        return "Taipei"
    }
    
    // MARK: - 監控控制
    
    func startMonitoring() {
        guard !stops.isEmpty, let route = selectedRoute else {
            errorMessage = "無法開始監控：沒有站點資料"
            print("❌ [Monitor] 無法開始監控：沒有站點資料")
            return
        }
        
        guard locationService.authorizationStatus == .authorizedAlways ||
              locationService.authorizationStatus == .authorizedWhenInUse else {
            errorMessage = "需要位置權限才能開始監控"
            print("❌ [Monitor] 需要位置權限才能開始監控")
            return
        }
        
        isMonitoring = true
        monitoringStartTime = Date()
        notifiedStops.removeAll()
        errorMessage = nil
        
        locationService.startUpdatingLocation()
        setupGeofencing()
        
        // 設置定時刷新實時到站資訊
        arrivalTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateEstimatedArrivalTimes()
        }
        
        updateEstimatedArrivalTimes()
        
        // 發送開始監控通知
        notificationService.sendNotification(
            title: "開始監控",
            body: "正在監控路線 \(route.RouteName.Zh_tw) (\(selectedDirection == 0 ? "去程" : "回程"))"
        )
        
        // 音頻播報開始監控
        if audioService.isAudioEnabled {
            var message = "開始監控路線\(route.RouteName.Zh_tw)"
            if let destination = destinationStopName {
                message += "，目的地\(destination)"
            }
            audioService.announceStationInfo(stopName: "監控開始", arrivalTime: message)
        }
        
        print("✅ [Monitor] 開始監控路線: \(route.RouteName.Zh_tw), 方向: \(selectedDirection == 0 ? "去程" : "回程"), 站點數: \(stops.count)")
    }
    
    func stopMonitoring() {
        isMonitoring = false
        monitoringStartTime = nil
        notifiedStops.removeAll()
        
        arrivalTimer?.invalidate()
        arrivalTimer = nil
        
        locationService.stopUpdatingLocation()
        locationService.stopMonitoringAllRegions()
        
        // 清除音頻目的地
        audioService.clearDestination()
        
        if let route = selectedRoute {
            notificationService.sendNotification(
                title: "停止監控",
                body: "已停止監控路線 \(route.RouteName.Zh_tw)"
            )
        }
        
        print("🛑 [Monitor] 已停止監控")
    }
    
    // MARK: - 地理圍欄設定
    
    private func setupGeofencing() {
        guard isMonitoring else { return }
        
        locationService.stopMonitoringAllRegions()
        
        for stop in stops {
            locationService.startMonitoringRegion(for: stop, radius: notifyDistance)
        }
        
        print("📍 [Monitor] 已設置 \(stops.count) 個地理圍欄，半徑: \(notifyDistance) 米")
    }
    
    // MARK: - 實時到站資訊
    
    private func updateEstimatedArrivalTimes() {
        guard let route = selectedRoute else { return }
        
        let city = determineCityFromCurrentLocation()
        
        tdxService.getEstimatedTimeOfArrival(city: city, routeName: route.RouteID) { [weak self] arrivals, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    print("⚠️ [Monitor] 更新到站資訊失敗: \(error.localizedDescription)")
                    return
                }
                
                guard let arrivals = arrivals else { return }
                
                let filteredArrivals = arrivals.filter { $0.Direction == self.selectedDirection }
                
                var newArrivals: [String: BusArrival] = [:]
                for arrival in filteredArrivals {
                    newArrivals[arrival.StopID] = arrival
                }
                
                self.arrivals = newArrivals
                print("⏰ [Monitor] 已更新 \(newArrivals.count) 個站點的到站資訊")
            }
        }
    }
    
    // MARK: - 位置更新處理
    
    private func handleLocationUpdate(_ location: CLLocation) {
        lastUserLocation = location
        
        guard isMonitoring else { return }
        
        updateNearestStop(userLocation: location)
        checkForStationNotifications(userLocation: location)
        
        // 檢查音頻提醒
        if audioService.isAudioEnabled {
            audioService.checkStationProximity(currentStops: stops, nearestStopIndex: nearestStopIndex)
        }
    }
    
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
    
    // MARK: - 最近站點更新
    
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
    
    // MARK: - 站點通知檢查
    
    private func checkForStationNotifications(userLocation: CLLocation) {
        for stop in stops {
            if notifiedStops.contains(stop.StopID) {
                continue
            }
            
            let stopLocation = CLLocation(
                latitude: stop.StopPosition.PositionLat,
                longitude: stop.StopPosition.PositionLon
            )
            
            let distance = userLocation.distance(from: stopLocation)
            
            if distance <= notifyDistance {
                notifiedStops.insert(stop.StopID)
                
                let arrival = arrivals[stop.StopID]
                let estimatedTimeText = arrival?.arrivalTimeText ?? "無到站資訊"
                
                // 一般通知
                let title = "接近站點: \(stop.StopName.Zh_tw)"
                let body = "距離: \(Int(distance))公尺\n公車到站: \(estimatedTimeText)"
                notificationService.sendNotification(title: title, body: body)
                
                // 音頻播報（如果不是目的地站點）
                if audioService.isAudioEnabled && destinationStopName != stop.StopName.Zh_tw {
                    audioService.announceStationInfo(
                        stopName: stop.StopName.Zh_tw,
                        arrivalTime: estimatedTimeText
                    )
                }
                
                print("🔔 [Monitor] 通知站點: \(stop.StopName.Zh_tw), 距離: \(Int(distance))m")
                
                // 檢查自動停止
                if autoStopMonitoring && isLastStop(stop) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.stopMonitoring()
                    }
                }
            }
        }
    }
    
    private func isLastStop(_ stop: BusStop.Stop) -> Bool {
        guard let lastStop = stops.last else { return false }
        return stop.StopID == lastStop.StopID
    }
    
    // MARK: - 實用方法
    
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
    
    func getMonitoringStats() -> (duration: TimeInterval, notifiedCount: Int, totalStops: Int) {
        let duration = monitoringStartTime?.timeIntervalSinceNow.magnitude ?? 0
        return (duration, notifiedStops.count, stops.count)
    }
    
    func resetNotificationStatus() {
        notifiedStops.removeAll()
        print("🔄 [Monitor] 已重置通知狀態")
    }
    
    func refreshData() {
        guard let route = selectedRoute else { return }
        fetchStops()
        
        if isMonitoring {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.setupGeofencing()
            }
        }
    }
    
    // MARK: - 音頻控制方法
    
    func toggleAudioMonitoring() {
        audioService.toggleAudioNotifications()
        isAudioMonitoringEnabled = audioService.isAudioEnabled
    }
    
    func adjustNotificationDistance(_ change: Int) {
        if change > 0 {
            audioService.increaseNotificationDistance()
        } else {
            audioService.decreaseNotificationDistance()
        }
        notificationStopsAhead = audioService.notificationDistance
    }
    
    // MARK: - 健康檢查
    
    func checkMonitoringHealth() -> (isHealthy: Bool, issues: [String]) {
        var issues: [String] = []
        
        let locationStatus = locationService.authorizationStatus
        if locationStatus != .authorizedAlways && locationStatus != .authorizedWhenInUse {
            issues.append("位置權限未授權")
        }
        
        if stops.isEmpty {
            issues.append("無站點資料")
        }
        
        if isMonitoring && arrivalTimer == nil {
            issues.append("到站資訊更新定時器未運行")
        }
        
        if isMonitoring && lastUserLocation == nil {
            issues.append("無法獲取位置資訊")
        }
        
        if let errorMessage = tdxService.errorMessage {
            issues.append("API 連線問題: \(errorMessage)")
        }
        
        // 檢查音頻服務狀態
        if !audioService.isHeadphonesConnected && audioService.isAudioEnabled {
            issues.append("建議連接耳機以獲得更好的音頻體驗")
        }
        
        return (issues.isEmpty, issues)
    }
    
    func forceStopMonitoring() {
        isMonitoring = false
        monitoringStartTime = nil
        notifiedStops.removeAll()
        errorMessage = nil
        
        arrivalTimer?.invalidate()
        arrivalTimer = nil
        
        locationService.stopUpdatingLocation()
        locationService.stopMonitoringAllRegions()
        audioService.clearDestination()
        
        print("🛑 [Monitor] 已強制停止監控")
    }
    
    // MARK: - 調試方法
    
    func debugCurrentState() {
        print("=== StationMonitoringService 狀態調試 ===")
        print("選擇的路線: \(selectedRoute?.RouteName.Zh_tw ?? "無")")
        print("路線ID: \(selectedRoute?.RouteID ?? "無")")
        print("選擇的方向: \(selectedDirection)")
        print("站點數量: \(stops.count)")
        print("是否正在載入: \(isLoading)")
        print("錯誤信息: \(errorMessage ?? "無")")
        print("是否正在監控: \(isMonitoring)")
        print("最近站點索引: \(nearestStopIndex?.description ?? "無")")
        print("已通知站點數: \(notifiedStops.count)")
        print("到站預估數據: \(arrivals.count) 筆")
        
        if !stops.isEmpty {
            print("前5個站點:")
            for (index, stop) in stops.prefix(5).enumerated() {
                let distance = distanceToStop(stop)
                let distanceText = distance == Double.infinity ? "無法計算" : "\(Int(distance))m"
                print("  \(index + 1). \(stop.StopName.Zh_tw) (序號: \(stop.StopSequence), 距離: \(distanceText))")
            }
        }
        
        let (isHealthy, issues) = checkMonitoringHealth()
        print("健康狀態: \(isHealthy ? "✅ 正常" : "⚠️ 有問題")")
        if !issues.isEmpty {
            print("問題列表:")
            for issue in issues {
                print("  - \(issue)")
            }
        }
        
        print("TDX服務狀態: 載入中=\(tdxService.isLoading), 錯誤=\(tdxService.errorMessage ?? "無")")
        print("位置服務狀態: \(locationService.authorizationStatus)")
        if let location = lastUserLocation {
            print("當前位置: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        } else {
            print("當前位置: 無")
        }
        print("========================================")
    }
}
