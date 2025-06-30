//
//  StationService.swift
//  Off2Go
//
//  Created by Heidie Lee on 2025/6/27.
//  修復版本：改善站點順序和到站時間匹配
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
    
    // 快取機制 - 調整時間
    private var stopsCache: [String: [BusStop]] = [:] // RouteID -> BusStop 陣列
    private var lastFetchTime: [String: Date] = [:] // RouteID -> 最後請求時間
    private var arrivalCache: [String: [BusArrival]] = [:] // RouteID -> 到站時間陣列
    private var lastArrivalFetchTime: [String: Date] = [:] // RouteID -> 最後到站時間請求時間
    
    private let cacheValidDuration: TimeInterval = 1800 // 30分鐘站點快取
    private let arrivalCacheValidDuration: TimeInterval = 45 // 45秒到站時間快取
    private let minimumFetchInterval: TimeInterval = 20 // 20秒最小請求間隔
    
    // 新增：全域請求控制（避免多個 StationService 實例同時請求）
    private static var globalLastRequestTime: Date?
    private static let globalMinimumInterval: TimeInterval = 10 // 全域10秒間隔
    private static var activeRequests: Set<String> = [] // 正在進行的請求
    
    private var arrivalUpdateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    deinit {
        stopArrivalUpdates()
        clearAllCaches()
        print("🗑️ [Station] StationService 已清理")
    }
    
    // MARK: - 設定路線（添加快取邏輯）
    
    func setRoute(_ route: BusRoute, direction: Int) {
        print("🚌 [Station] === 設定路線與方向（增強版）===")
        print("   路線: \(route.RouteName.Zh_tw)")
        print("   方向: \(direction == 0 ? "去程" : "回程")")
        print("   上一個方向: \(selectedDirection == 0 ? "去程" : "回程")")
        
        let isDirectionChange = (selectedRoute?.RouteID == route.RouteID) && (selectedDirection != direction)
        let isRouteChange = selectedRoute?.RouteID != route.RouteID
        
        // 更新狀態
        selectedRoute = route
        selectedDirection = direction
        
        if isDirectionChange {
            print("🔄 [Station] *** 偵測到方向切換，強制重新處理 ***")
            // 方向切換時：清除當前顯示並強制重新處理
            stops.removeAll()
            arrivals.removeAll()
        }
        
        if isRouteChange {
            print("🔄 [Station] 偵測到路線切換")
            stops.removeAll()
            arrivals.removeAll()
        }
        
        // 檢查快取
        if let cachedStops = getCachedStops(for: route.RouteID), !cachedStops.isEmpty {
            print("📦 [Station] 使用快取資料\(isDirectionChange ? "（強制重新處理方向）" : "")")
            processStopsFromCache(cachedStops, direction: direction)
            return
        }
        
        // 重置狀態並重新獲取
        print("🔄 [Station] 重新獲取站點資料")
        stops.removeAll()
        arrivals.removeAll()
        errorMessage = nil
        
        fetchStops()
    }
    
    // MARK: - 快取管理方法（修復版）
    
    private func getCachedStops(for routeID: String) -> [BusStop]? {
        guard let cachedStops = stopsCache[routeID],
              let lastFetch = lastFetchTime[routeID] else {
            print("📦 [Station] 無站點快取: \(routeID)")
            return nil
        }
        
        let timeSinceLastFetch = Date().timeIntervalSince(lastFetch)
        let isValid = timeSinceLastFetch < cacheValidDuration
        
        print("📦 [Station] 站點快取檢查: \(routeID), 經過時間: \(Int(timeSinceLastFetch))秒, 有效: \(isValid)")
        
        return isValid ? cachedStops : nil
    }
    
    private func getCachedArrivals(for routeID: String) -> [BusArrival]? {
        guard let cachedArrivals = arrivalCache[routeID],
              let lastFetch = lastArrivalFetchTime[routeID] else {
            print("📦 [Station] 無到站時間快取: \(routeID)")
            return nil
        }
        
        let timeSinceLastFetch = Date().timeIntervalSince(lastFetch)
        let isValid = timeSinceLastFetch < arrivalCacheValidDuration
        
        print("📦 [Station] 到站時間快取檢查: \(routeID), 經過時間: \(Int(timeSinceLastFetch))秒, 有效: \(isValid)")
        
        return isValid ? cachedArrivals : nil
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
        guard let route = selectedRoute else {
            print("❌ [Station] 找不到選擇的路線")
            fetchStops()
            return
        }
        
        print("📦 [Station] === 從快取處理（方向:\(direction == 0 ? "去程" : "回程")，路線數:\(stopsData.count)）===")
        
        // 選擇對應方向的路線資料
        guard let selectedBusStop = selectCorrectRouteByDirection(stopsData, route: route, direction: direction) else {
            print("❌ [Station] 找不到方向 \(direction) 的路線資料")
            print("   可能原因：")
            print("   1. 該方向確實沒有資料")
            print("   2. 路線資料結構異常")
            print("   → 清除快取並重新獲取")
            
            stopsCache.removeValue(forKey: route.RouteID)
            lastFetchTime.removeValue(forKey: route.RouteID)
            fetchStops()
            return
        }
        
        // 處理站點順序
        let processedStops = processStopsByDirection(selectedBusStop.Stops, direction: direction)
        
        if processedStops.isEmpty {
            errorMessage = "該方向暫無站點資料"
            print("❌ [Station] 處理後無站點資料")
        } else {
            stops = processedStops
            print("✅ [Station] 快取載入完成")
            print("   最終站點數: \(processedStops.count)")
            print("   起終點: \(processedStops.first?.StopName.Zh_tw ?? "無") → \(processedStops.last?.StopName.Zh_tw ?? "無")")
            
            // 清除舊的到站時間
            arrivals.removeAll()
            
            // 檢查到站時間快取
            if let cachedArrivals = getCachedArrivals(for: route.RouteID) {
                updateArrivalsFromCache(cachedArrivals)
            }
            
            startArrivalUpdates()
        }
    }
    
    private func selectCorrectRouteByDirection(_ stopsData: [BusStop], route: BusRoute, direction: Int) -> BusStop? {
        print("🔍 [Station] === 選擇正確方向的路線資料 ===")
        print("   目標方向: \(direction == 0 ? "去程" : "回程")")
        print("   可用路線數: \(stopsData.count)")
        print("   關鍵理解：TDX API 已經為每個方向提供正確的路線資料")
        
        // 詳細分析每條路線
        for (index, busStop) in stopsData.enumerated() {
            let sortedStops = busStop.Stops.sorted { $0.StopSequence < $1.StopSequence }
            print("   路線資料\(index + 1) (預期\(index == 0 ? "去程" : "回程")):")
            print("     RouteID: \(busStop.RouteID)")
            print("     站點數: \(sortedStops.count)")
            
            if !sortedStops.isEmpty {
                let firstStop = sortedStops.first!
                let lastStop = sortedStops.last!
                print("     實際路線: \(firstStop.StopName.Zh_tw) → \(lastStop.StopName.Zh_tw)")
                print("     序號範圍: \(firstStop.StopSequence) → \(lastStop.StopSequence)")
            }
        }
        
        if stopsData.count >= 2 {
            if direction == 0 {
                // 去程：選擇第一條路線
                let selectedRoute = stopsData[0]
                print("✅ [Station] 去程：選擇第一條路線")
                print("   將直接按序號順序顯示，不反轉")
                return selectedRoute
            } else {
                // 回程：選擇第二條路線
                let selectedRoute = stopsData[1]
                print("✅ [Station] 回程：選擇第二條路線")
                print("   將直接按序號順序顯示，不反轉")
                print("   因為TDX已經提供回程的正確路線順序")
                return selectedRoute
            }
        } else if stopsData.count == 1 {
            print("✅ [Station] 只有一條路線資料")
            return stopsData[0]
        } else {
            print("❌ [Station] 無路線資料")
            return nil
        }
    }
    
    private func updateArrivalsFromCache(_ arrivals: [BusArrival]) {
        print("🔄 [Station] 更新到站時間快取 - 當前方向: \(selectedDirection)")
        print("🔄 [Station] 當前站點數: \(stops.count)")
        
        // 分析到站資料的方向分布
        let directionGroups = Dictionary(grouping: arrivals) { $0.Direction }
        print("📊 [Station] 到站資料方向分布:")
        for (direction, dirArrivals) in directionGroups.sorted(by: { $0.key < $1.key }) {
            print("   方向 \(direction): \(dirArrivals.count) 筆")
            let sampleStopIDs = dirArrivals.prefix(3).map { $0.StopID }
            print("     前3個StopID: \(sampleStopIDs)")
        }
        
        var newArrivals: [String: BusArrival] = [:]
        
        // 改進的匹配策略：
        // 1. 優先用方向匹配
        // 2. 如果沒有匹配，嘗試反向方向
        // 3. 最後忽略方向限制
        
        let strategies: [(name: String, filter: (BusArrival) -> Bool)] = [
            ("直接方向匹配", { $0.Direction == self.selectedDirection }),
            ("反向方向匹配", { $0.Direction == (self.selectedDirection == 0 ? 1 : 0) }),
            ("忽略方向", { _ in true })
        ]
        
        for strategy in strategies {
            let filteredArrivals = arrivals.filter(strategy.filter)
            
            if !filteredArrivals.isEmpty {
                print("✅ [Station] 使用策略：\(strategy.name), 可用資料：\(filteredArrivals.count) 筆")
                
                // 為當前顯示的站點尋找對應的到站時間
                for stop in stops {
                    if let matchingArrival = filteredArrivals.first(where: { $0.StopID == stop.StopID }) {
                        newArrivals[stop.StopID] = matchingArrival
                    }
                }
                
                // 如果成功匹配到足夠的站點，就停止嘗試其他策略
                let matchRate = Double(newArrivals.count) / Double(stops.count)
                print("📊 [Station] 匹配率: \(String(format: "%.1f", matchRate * 100))% (\(newArrivals.count)/\(stops.count))")
                
                if matchRate > 0.3 { // 如果匹配率超過30%，就使用這個結果
                    break
                } else {
                    newArrivals.removeAll() // 清空，嘗試下一個策略
                }
            }
        }
        
        self.arrivals = newArrivals
        print("✅ [Station] 最終匹配到 \(newArrivals.count) 個站點的到站時間")
        
        // 顯示匹配詳情（除錯用）
        if !newArrivals.isEmpty {
            let stopsWithArrival = stops.filter { newArrivals[$0.StopID] != nil }.prefix(3)
            for stop in stopsWithArrival {
                if let arrival = newArrivals[stop.StopID] {
                    print("   ✓ \(stop.StopName.Zh_tw): \(arrival.arrivalTimeText)")
                }
            }
        }
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
        
        // 修改請求間隔控制：降低最小間隔避免過度限制
        if let lastFetch = lastFetchTime[route.RouteID],
           Date().timeIntervalSince(lastFetch) < 5.0 {  // 降低為5秒
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
                guard let busStop = self.selectCorrectRouteByDirection(stopsData, route: route, direction: self.selectedDirection) else {
                    self.errorMessage = "找不到匹配方向 \(self.selectedDirection) 的路線資料"
                    print("❌ [Station] 找不到匹配方向 \(self.selectedDirection) 的路線資料")
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
    
    // MARK: - 到站時間更新（修復版本）
    
    private func startArrivalUpdates() {
        stopArrivalUpdates() // 確保只有一個 Timer
        
        // 立即更新一次（可能使用快取）
        updateArrivalTimes()
        
        // 每60秒更新一次（保持合理頻率）
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
        
        let routeID = route.RouteID
        
        // 全域請求頻率控制（避免多個 StationService 同時請求）
        let now = Date()
        if let globalLastRequest = Self.globalLastRequestTime,
           now.timeIntervalSince(globalLastRequest) < Self.globalMinimumInterval {
            print("🚫 [Station] 全域請求間隔控制，跳過請求")
            return
        }
        
        // 檢查是否已有相同請求在進行中
        if Self.activeRequests.contains(routeID) {
            print("🚫 [Station] 相同路線正在請求中，跳過請求: \(routeID)")
            return
        }
        
        // 先檢查快取
        if let cachedArrivals = getCachedArrivals(for: routeID) {
            print("📦 [Station] 使用有效的到站時間快取")
            updateArrivalsFromCache(cachedArrivals)
            return
        }
        
        // 檢查個別路線請求間隔
        if let lastFetch = lastArrivalFetchTime[routeID],
           now.timeIntervalSince(lastFetch) < minimumFetchInterval {
            print("⚠️ [Station] 路線請求間隔控制，跳過請求: \(routeID)")
            return
        }
        
        // 更新全域和路線請求時間
        Self.globalLastRequestTime = now
        lastArrivalFetchTime[routeID] = now
        Self.activeRequests.insert(routeID)
        
        let city = determineCityFromRoute()
        
        print("🔄 [Station] 執行 API 請求：\(route.RouteName.Zh_tw)")
        
        tdxService.getEstimatedTimeOfArrival(city: city, routeName: routeID) { [weak self] arrivals, error in
            guard let self = self else {
                Self.activeRequests.remove(routeID)
                return
            }
            
            DispatchQueue.main.async {
                // 移除活動請求標記
                Self.activeRequests.remove(routeID)
                
                if let arrivals = arrivals {
                    // 快取到站時間
                    self.cacheArrivals(arrivals, for: routeID)
                    
                    // 更新顯示
                    self.updateArrivalsFromCache(arrivals)
                    print("✅ [Station] 成功更新到站時間: \(route.RouteName.Zh_tw)")
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
    
    private func processStopsByDirection(_ stops: [BusStop.Stop], direction: Int) -> [BusStop.Stop] {
        print("🔄 [Station] === 處理站點順序（修正版：不反轉）===")
        print("   請求方向: \(direction == 0 ? "去程" : "回程")")
        print("   原始站點數: \(stops.count)")
        
        if stops.isEmpty {
            print("   ❌ 無站點資料")
            return stops
        }
        
        // 按序號排序，但不反轉！因為TDX已經返回正確方向的路線
        let sortedStops = stops.sorted { $0.StopSequence < $1.StopSequence }
        
        print("   站點資訊分析:")
        print("     序號範圍: \(sortedStops.first?.StopSequence ?? 0) → \(sortedStops.last?.StopSequence ?? 0)")
        print("     起點: \(sortedStops.first?.StopName.Zh_tw ?? "無")")
        print("     終點: \(sortedStops.last?.StopName.Zh_tw ?? "無")")
        
        // 重要修正：不管去程還是回程，都按序號順序顯示
        // 因為TDX API已經返回了對應方向的正確路線資料
        let finalStops = sortedStops
        
        print("   ✅ 直接按序號順序顯示（序號小→大）")
        print("   理由：TDX API已返回正確方向的路線，無需反轉")
        
        print("   最終結果:")
        print("     站點數: \(finalStops.count)")
        print("     實際起點: \(finalStops.first?.StopName.Zh_tw ?? "無")")
        print("     實際終點: \(finalStops.last?.StopName.Zh_tw ?? "無")")
        
        // 顯示前3個和後3個站點確認順序
        print("   前3個站點:")
        for (index, stop) in finalStops.prefix(3).enumerated() {
            print("     \(index + 1). \(stop.StopName.Zh_tw) (序號:\(stop.StopSequence))")
        }
        
        if finalStops.count > 6 {
            print("   後3個站點:")
            for (index, stop) in finalStops.suffix(3).enumerated() {
                let actualIndex = finalStops.count - 3 + index + 1
                print("     \(actualIndex). \(stop.StopName.Zh_tw) (序號:\(stop.StopSequence))")
            }
        }
        
        return finalStops
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
            Self.activeRequests.remove(routeID)
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
        Self.activeRequests.removeAll()
    }
    
    func getCacheInfo() -> String {
        let stopsCount = stopsCache.count
        let arrivalsCount = arrivalCache.count
        let activeCount = Self.activeRequests.count
        return "站點快取: \(stopsCount), 到站時間快取: \(arrivalsCount), 活動請求: \(activeCount)"
    }
}
