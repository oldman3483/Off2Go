//
//  StationService.swift
//  Off2Go
//
//  Created by Heidie Lee on 2025/6/27.
//  簡化的站點資料服務，移除複雜的監控邏輯，添加快取機制
//

import Foundation
import CoreLocation
import Combine

class StationService: ObservableObject {
    private let tdxService = TDXService.shared
    
    @Published var selectedRoute: BusRoute?
    @Published var selectedDirection: Int = 0
    @Published var stops: [BusStop.Stop] = []
    @Published var arrivals: [String: BusArrival] = [:]
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // 新增：快取機制
    private var stopsCache: [String: [BusStop]] = [:] // RouteID -> BusStop 陣列
    private var lastFetchTime: [String: Date] = [:] // RouteID -> 最後請求時間
    private var arrivalCache: [String: [BusArrival]] = [:] // RouteID -> 到站時間陣列
    private var lastArrivalFetchTime: [String: Date] = [:] // RouteID -> 最後到站時間請求時間
    
    private let cacheValidDuration: TimeInterval = 300 // 5分鐘站點快取
    private let arrivalCacheValidDuration: TimeInterval = 30 // 30秒到站時間快取
    private let minimumFetchInterval: TimeInterval = 10 // 最小請求間隔10秒
    
    private var arrivalUpdateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    deinit {
        stopArrivalUpdates()
        clearAllCaches()
    }
    
    // MARK: - 設定路線（添加快取邏輯）
    
    func setRoute(_ route: BusRoute, direction: Int) {
        print("🚌 [Station] 設定路線: \(route.RouteName.Zh_tw) (方向: \(direction))")
        
        selectedRoute = route
        selectedDirection = direction
        
        // 檢查是否只是方向改變且有快取資料
        if let cachedStops = getCachedStops(for: route.RouteID), !cachedStops.isEmpty {
            print("📦 [Station] 使用快取的站點資料")
            processStopsFromCache(cachedStops, direction: direction)
            return
        }
        
        // 重置狀態
        stops.removeAll()
        arrivals.removeAll()
        errorMessage = nil
        
        fetchStops()
    }
    
    // MARK: - 快取管理方法
    
    private func getCachedStops(for routeID: String) -> [BusStop]? {
        guard let cachedStops = stopsCache[routeID],
              let lastFetch = lastFetchTime[routeID],
              Date().timeIntervalSince(lastFetch) < cacheValidDuration else {
            print("📦 [Station] 站點快取過期或不存在: \(routeID)")
            return nil
        }
        print("📦 [Station] 找到有效的站點快取: \(routeID)")
        return cachedStops
    }
    
    private func getCachedArrivals(for routeID: String) -> [BusArrival]? {
        guard let cachedArrivals = arrivalCache[routeID],
              let lastFetch = lastArrivalFetchTime[routeID],
              Date().timeIntervalSince(lastFetch) < arrivalCacheValidDuration else {
            print("📦 [Station] 到站時間快取過期或不存在: \(routeID)")
            return nil
        }
        print("📦 [Station] 找到有效的到站時間快取: \(routeID)")
        return cachedArrivals
    }
    
    private func cacheStops(_ stopsData: [BusStop], for routeID: String) {
        stopsCache[routeID] = stopsData
        lastFetchTime[routeID] = Date()
        print("📦 [Station] 已快取站點資料: \(routeID), 數量: \(stopsData.count)")
    }
    
    private func cacheArrivals(_ arrivals: [BusArrival], for routeID: String) {
        arrivalCache[routeID] = arrivals
        lastArrivalFetchTime[routeID] = Date()
        print("📦 [Station] 已快取到站時間: \(routeID), 數量: \(arrivals.count)")
    }
    
    private func processStopsFromCache(_ stopsData: [BusStop], direction: Int) {
        guard let route = selectedRoute,
              let busStop = findMatchingRoute(stopsData, targetRoute: route) else {
            print("❌ [Station] 快取資料中找不到匹配路線")
            fetchStops() // 回退到重新請求
            return
        }
        
        let processedStops = processStopsByDirection(busStop.Stops, direction: direction)
        
        if processedStops.isEmpty {
            errorMessage = "該方向暫無站點資料"
        } else {
            stops = processedStops
            print("✅ [Station] 從快取載入完成：\(processedStops.count) 個站點")
            
            // 檢查是否有快取的到站時間
            if let route = selectedRoute,
               let cachedArrivals = getCachedArrivals(for: route.RouteID) {
                updateArrivalsFromCache(cachedArrivals)
            }
            
            // 開始定期更新到站時間
            startArrivalUpdates()
        }
    }
    
    private func updateArrivalsFromCache(_ arrivals: [BusArrival]) {
        let filteredArrivals = arrivals.filter { $0.Direction == selectedDirection }
        
        var newArrivals: [String: BusArrival] = [:]
        for arrival in filteredArrivals {
            newArrivals[arrival.StopID] = arrival
        }
        
        self.arrivals = newArrivals
        print("📦 [Station] 從快取更新 \(newArrivals.count) 個站點的到站時間")
    }
    
    private func clearAllCaches() {
        stopsCache.removeAll()
        lastFetchTime.removeAll()
        arrivalCache.removeAll()
        lastArrivalFetchTime.removeAll()
        print("🗑️ [Station] 已清除所有快取")
    }
    
    // MARK: - 獲取站點資料（添加防重複請求）
    
    private func fetchStops() {
        guard let route = selectedRoute else {
            errorMessage = "沒有選擇路線"
            return
        }
        
        // 檢查是否最近才請求過（防止重複請求）
        if let lastFetch = lastFetchTime[route.RouteID],
           Date().timeIntervalSince(lastFetch) < minimumFetchInterval {
            print("⚠️ [Station] 最近才請求過站點資料，跳過重複請求")
            return
        }
        
        print("🔄 [Station] === 開始獲取站點資料 ===")
        print("   路線: \(route.RouteName.Zh_tw)")
        print("   RouteID: \(route.RouteID)")
        print("   方向: \(selectedDirection)")
        
        isLoading = true
        errorMessage = nil
        
        let city = determineCityFromRoute()
        
        // 記錄請求時間（防止重複請求）
        lastFetchTime[route.RouteID] = Date()
        
        tdxService.getStops(city: city, routeName: route.RouteID) { [weak self] busStops, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "獲取站點失敗: \(error.localizedDescription)"
                    print("❌ [Station] \(self.errorMessage!)")
                    return
                }
                
                guard let stopsData = busStops, !stopsData.isEmpty else {
                    self.errorMessage = "無站點資料"
                    print("❌ [Station] 無站點資料")
                    return
                }
                
                // 快取站點資料
                self.cacheStops(stopsData, for: route.RouteID)
                
                // 找到匹配的路線
                guard let busStop = self.findMatchingRoute(stopsData, targetRoute: route) else {
                    self.errorMessage = "找不到匹配的路線資料"
                    print("❌ [Station] 找不到匹配的路線資料")
                    
                    // 除錯資訊
                    let availableRouteIDs = stopsData.map { $0.RouteID }
                    print("📋 [Station] 可用的路線ID: \(availableRouteIDs)")
                    
                    return
                }
                
                // 處理站點順序
                let processedStops = self.processStopsByDirection(busStop.Stops, direction: self.selectedDirection)
                
                if processedStops.isEmpty {
                    self.errorMessage = "該方向暫無站點資料"
                } else {
                    self.stops = processedStops
                    print("✅ [Station] 載入完成：\(processedStops.count) 個站點")
                    
                    // 開始定期更新到站時間
                    self.startArrivalUpdates()
                }
            }
        }
    }
    
    // MARK: - 到站時間更新（添加快取和頻率控制）
    
    private func startArrivalUpdates() {
        stopArrivalUpdates()
        
        // 立即更新一次（可能使用快取）
        updateArrivalTimes()
        
        // 改為每60秒更新一次（降低請求頻率）
        arrivalUpdateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateArrivalTimes()
        }
        
        print("⏰ [Station] 開始定期更新到站時間（每60秒）")
    }
    
    private func stopArrivalUpdates() {
        arrivalUpdateTimer?.invalidate()
        arrivalUpdateTimer = nil
        print("⏹️ [Station] 停止到站時間更新")
    }
    
    private func updateArrivalTimes() {
        guard let route = selectedRoute else { return }
        
        // 先檢查快取
        if let cachedArrivals = getCachedArrivals(for: route.RouteID) {
            print("📦 [Station] 使用快取的到站時間")
            updateArrivalsFromCache(cachedArrivals)
            return
        }
        
        // 檢查是否最近才請求過到站時間
        if let lastFetch = lastArrivalFetchTime[route.RouteID],
           Date().timeIntervalSince(lastFetch) < 20.0 { // 20秒內不重複請求到站時間
            print("⚠️ [Station] 最近才請求過到站時間，跳過重複請求")
            return
        }
        
        let city = determineCityFromRoute()
        
        print("🔄 [Station] 請求新的到站時間資料")
        
        // 記錄請求時間
        lastArrivalFetchTime[route.RouteID] = Date()
        
        tdxService.getEstimatedTimeOfArrival(city: city, routeName: route.RouteID) { [weak self] arrivals, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let arrivals = arrivals {
                    // 快取到站時間
                    self.cacheArrivals(arrivals, for: route.RouteID)
                    
                    // 更新顯示
                    self.updateArrivalsFromCache(arrivals)
                } else if let error = error {
                    print("❌ [Station] 獲取到站時間失敗: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - 輔助方法
    
    private func determineCityFromRoute() -> String {
        print("🔍 [Station] === 城市判斷邏輯 ===")
        
        // 方法1：檢查 UserDefaults 中的選擇城市
        if let savedCity = UserDefaults.standard.string(forKey: "selectedCity") {
            print("🏙️ [Station] 從 UserDefaults 獲取城市: \(savedCity)")
            return savedCity
        }
        
        // 方法2：從路線物件獲取城市資訊（如果有的話）
        if let route = selectedRoute, let city = route.city {
            print("🏙️ [Station] 從路線物件獲取城市: \(city)")
            return city
        }
        
        // 方法3：根據路線名稱判斷（701在新北市）
        if let route = selectedRoute {
            let routeName = route.RouteName.Zh_tw
            print("🔍 [Station] 根據路線名稱判斷: \(routeName)")
            
            // 701 路線在新北市
            if routeName == "701" {
                print("🏙️ [Station] 701路線確定為新北市")
                return "NewTaipei"
            }
            
            // 其他新北市路線判斷
            if routeName.hasPrefix("9") ||
               routeName == "264" || routeName == "307" ||
               routeName.contains("副") {
                print("🏙️ [Station] 根據特徵判斷為新北市")
                return "NewTaipei"
            }
            
            // 台北市特色路線
            if routeName.contains("紅") || routeName.contains("藍") ||
               routeName.contains("綠") || routeName.contains("橘") ||
               routeName.contains("棕") || routeName.contains("黃") {
                print("🏙️ [Station] 根據顏色判斷為台北市")
                return "Taipei"
            }
        }
        
        // 預設（不應該發生）
        print("⚠️ [Station] 警告：無法確定城市，使用預設新北市")
        return "NewTaipei" // 改為預設新北市
    }
    
    private func findMatchingRoute(_ stopsData: [BusStop], targetRoute: BusRoute) -> BusStop? {
        print("🔍 [Station] === 尋找匹配路線 ===")
        print("   目標 RouteID: \(targetRoute.RouteID)")
        print("   目標 RouteName: \(targetRoute.RouteName.Zh_tw)")
        print("   可用資料數量: \(stopsData.count)")
        
        // 列出所有可用的路線
        for (index, busStop) in stopsData.enumerated() {
            print("   可用路線\(index + 1): RouteID=\(busStop.RouteID), 站點數=\(busStop.Stops.count)")
        }
        
        // 完全匹配 RouteID
        if let exactMatch = stopsData.first(where: { $0.RouteID == targetRoute.RouteID }) {
            print("✅ [Station] 找到完全匹配的RouteID: \(exactMatch.RouteID)")
            return exactMatch
        }
        
        // 忽略大小寫匹配 RouteID
        if let caseInsensitiveMatch = stopsData.first(where: {
            $0.RouteID.lowercased() == targetRoute.RouteID.lowercased()
        }) {
            print("✅ [Station] 找到忽略大小寫匹配的RouteID: \(caseInsensitiveMatch.RouteID)")
            return caseInsensitiveMatch
        }
        
        // 包含匹配 RouteID
        if let containsMatch = stopsData.first(where: { busStop in
            busStop.RouteID.contains(targetRoute.RouteID) ||
            targetRoute.RouteID.contains(busStop.RouteID)
        }) {
            print("✅ [Station] 找到包含匹配的RouteID: \(containsMatch.RouteID)")
            return containsMatch
        }
        
        // 路線名稱匹配
        if let nameMatch = stopsData.first(where: { busStop in
            busStop.RouteID == targetRoute.RouteName.Zh_tw ||
            busStop.RouteID.contains(targetRoute.RouteName.Zh_tw)
        }) {
            print("✅ [Station] 找到名稱匹配: \(nameMatch.RouteID)")
            return nameMatch
        }
        
        // 如果只有一筆資料，直接使用
        if stopsData.count == 1 {
            let singleResult = stopsData[0]
            print("✅ [Station] 只有一筆資料，直接使用: \(singleResult.RouteID)")
            return singleResult
        }
        
        print("❌ [Station] 無法找到匹配的路線")
        return nil
    }
    
    private func processStopsByDirection(_ stops: [BusStop.Stop], direction: Int) -> [BusStop.Stop] {
        let sortedStops = stops.sorted { $0.StopSequence < $1.StopSequence }
        
        if direction == 1 {
            return Array(sortedStops.reversed())
        } else {
            return sortedStops
        }
    }
    
    // MARK: - 公開方法
    
    func refreshData() {
        guard let route = selectedRoute else { return }
        
        // 清除特定路線的快取
        if let routeID = selectedRoute?.RouteID {
            stopsCache.removeValue(forKey: routeID)
            lastFetchTime.removeValue(forKey: routeID)
            arrivalCache.removeValue(forKey: routeID)
            lastArrivalFetchTime.removeValue(forKey: routeID)
            print("🗑️ [Station] 已清除路線 \(routeID) 的快取")
        }
        
        setRoute(route, direction: selectedDirection)
    }
    
    func getArrivalTime(for stopID: String) -> String? {
        return arrivals[stopID]?.arrivalTimeText
    }
    
    // MARK: - 快取管理公開方法
    
    func clearCache() {
        clearAllCaches()
    }
    
    func getCacheInfo() -> String {
        let stopsCount = stopsCache.count
        let arrivalsCount = arrivalCache.count
        return "站點快取: \(stopsCount), 到站時間快取: \(arrivalsCount)"
    }
}
