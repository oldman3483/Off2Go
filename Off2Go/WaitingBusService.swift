//
//  WaitingBusService.swift - 優化版
//  Off2Go
//
//  簡化版本：統一音頻服務調用，修復語音播報問題
//

import Foundation
import Combine
import UserNotifications

class WaitingBusService: ObservableObject {
    static let shared = WaitingBusService()
    
    @Published var activeAlerts: [WaitingBusAlert] = []
    
    private let tdxService = TDXService.shared
    
    private var refreshTimer: Timer?
    private var notifiedAlerts: Set<UUID> = []
    
    // 簡化：直接引用共享的音頻服務
    private var audioService: AudioNotificationService {
        return AudioNotificationService.shared
    }
    
    private init() {
        loadActiveAlerts()
        startRefreshTimer()
        print("🚌 [WaitingBus] WaitingBusService 初始化完成")
    }
    
    // MARK: - 基本等車提醒管理
    
    func addWaitingAlert(routeName: String, stopName: String, stopID: String, direction: Int, alertMinutes: Int = 3) {
        // 檢查是否已存在相同的提醒
        if hasWaitingAlert(for: stopID) {
            print("⚠️ [WaitingBus] 站點 \(stopID) 已有等車提醒")
            return
        }
        
        let alert = WaitingBusAlert(
            routeName: routeName,
            stopName: stopName,
            stopID: stopID,
            direction: direction,
            alertMinutes: alertMinutes
        )
        
        activeAlerts.append(alert)
        saveActiveAlerts()
        
        // 改用等車提醒的播報邏輯
        let confirmMessage = "已設定\(routeName) \(stopName)等車提醒，將在公車到站前\(alertMinutes)分鐘通知您"
        audioService.announceWaitingBusAlert(confirmMessage)
        
        print("✅ [WaitingBus] 新增等車提醒: \(routeName) - \(stopName) (提前\(alertMinutes)分鐘)")
    }
    
    func removeWaitingAlert(for stopID: String) {
        // 先找到對應的 alert
        guard let alert = activeAlerts.first(where: { $0.stopID == stopID }) else {
            print("⚠️ [WaitingBus] 找不到 stopID \(stopID) 的等車提醒")
            return
        }
        
        // 使用現有的 removeWaitingAlert 方法
        removeWaitingAlert(alert)
    }
    
    func removeWaitingAlert(_ alert: WaitingBusAlert) {
        let routeName = alert.routeName
        let stopName = alert.stopName
        
        // 移除提醒和通知狀態
        activeAlerts.removeAll { $0.id == alert.id }
        notifiedAlerts.remove(alert.id)
        saveActiveAlerts()
        
        // 確認取消成功（僅在非自動移除時播放，且改用等車提醒的播報邏輯）
        if !isAutoRemoving {
            let cancelMessage = "已取消\(routeName) \(stopName)的等車提醒"
            audioService.announceWaitingBusAlert(cancelMessage)
        }
        
        print("🗑️ [WaitingBus] 移除等車提醒: \(routeName) - \(stopName)")
    }
    
    private var isAutoRemoving = false
    
    private func autoRemoveAlert(_ alert: WaitingBusAlert) {
        isAutoRemoving = true
        removeWaitingAlert(alert)
        isAutoRemoving = false
    }

    
    func hasWaitingAlert(for stopID: String) -> Bool {
        return activeAlerts.contains { $0.stopID == stopID && $0.isActive }
    }
    
    func getWaitingAlert(for stopID: String) -> WaitingBusAlert? {
        return activeAlerts.first { $0.stopID == stopID && $0.isActive }
    }
    
    // MARK: - 到站時間檢查（優化版）
    
    private func checkArrivalTimes() {
        // 清理過期提醒
        let validAlerts = activeAlerts.filter { $0.isActive }
        if validAlerts.count != activeAlerts.count {
            activeAlerts = validAlerts
            saveActiveAlerts()
            print("🧹 [WaitingBus] 清理了 \(activeAlerts.count - validAlerts.count) 個過期提醒")
        }
        
        guard !activeAlerts.isEmpty else {
            print("📝 [WaitingBus] 無等車提醒需要檢查")
            return
        }
        
        print("🔍 [WaitingBus] 開始檢查 \(activeAlerts.count) 個等車提醒")
        
        // 按路線分組，減少API請求
        let groupedAlerts = Dictionary(grouping: activeAlerts) { $0.routeName }
        
        for (routeName, alerts) in groupedAlerts {
            // 跳過已通知的提醒
            let pendingAlerts = alerts.filter { !notifiedAlerts.contains($0.id) }
            if pendingAlerts.isEmpty { continue }
            
            checkAlertsForRoute(routeName: routeName, alerts: pendingAlerts)
        }
    }
    
    private func checkAlertsForRoute(routeName: String, alerts: [WaitingBusAlert]) {
        let city = determineCityFromRoute(routeName)
        
        // 使用實際的RouteID進行查詢
        let routeID = extractRouteID(from: routeName)
        
        print("📡 [WaitingBus] 查詢路線到站時間: \(routeName) (RouteID: \(routeID))")
        
        tdxService.getEstimatedTimeOfArrival(city: city, routeName: routeID) { [weak self] arrivals, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let arrivals = arrivals, !arrivals.isEmpty {
                    self.processArrivalDataForAlerts(alerts: alerts, arrivals: arrivals)
                } else {
                    print("❌ [WaitingBus] 無法獲取路線 \(routeName) 的到站時間")
                    if let error = error {
                        print("   錯誤: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func processArrivalDataForAlerts(alerts: [WaitingBusAlert], arrivals: [BusArrival]) {
        print("📊 [WaitingBus] 處理到站資料：\(arrivals.count) 筆到站資訊")
        
        for alert in alerts {
            // 尋找匹配的到站資料
            let matchingArrivals = arrivals.filter { arrival in
                arrival.StopID == alert.stopID && arrival.Direction == alert.direction
            }
            
            if let arrival = matchingArrivals.first {
                processAlertWithArrival(alert: alert, arrival: arrival)
            } else {
                print("⚠️ [WaitingBus] 找不到站點 \(alert.stopName) 的到站資料")
            }
        }
    }
    
    private func processAlertWithArrival(alert: WaitingBusAlert, arrival: BusArrival) {
        guard let estimatedTime = arrival.EstimateTime else {
            print("⚠️ [WaitingBus] 站點 \(alert.stopName) 無預估到站時間")
            return
        }
        
        let minutesToArrival = estimatedTime / 60
        print("⏰ [WaitingBus] \(alert.routeName) 到 \(alert.stopName) 還有 \(minutesToArrival) 分鐘")
        
        // 檢查是否已經通知過
        if notifiedAlerts.contains(alert.id) {
            // 如果已經通知過且時間很短，自動移除提醒
            if estimatedTime <= 30 { // 30秒內
                print("🗑️ [WaitingBus] 公車已到站，自動移除提醒: \(alert.routeName) - \(alert.stopName)")
                removeWaitingAlert(alert)
            }
            return
        }
        
        // 檢查是否需要觸發提醒
        if minutesToArrival <= alert.alertMinutes && minutesToArrival > 0 {
            // 接近提醒
            triggerBusApproachingAlert(alert: alert, minutesToArrival: minutesToArrival)
            notifiedAlerts.insert(alert.id)
            
            // 設定自動移除計時器（公車到站後自動移除）
            let autoRemoveTime = TimeInterval(estimatedTime + 60) // 預估時間 + 1分鐘緩衝
            DispatchQueue.main.asyncAfter(deadline: .now() + autoRemoveTime) { [weak self] in
                guard let self = self else { return }
                
                if self.activeAlerts.contains(where: { $0.id == alert.id }) {
                    print("⏰ [WaitingBus] 自動移除過期提醒: \(alert.routeName) - \(alert.stopName)")
                    self.removeWaitingAlert(alert)
                }
            }
            
        } else if estimatedTime <= 60 { // 60秒內
            // 立即到站提醒
            triggerBusArrivedAlert(alert: alert)
            notifiedAlerts.insert(alert.id)
            
            // 30秒後自動移除提醒
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                guard let self = self else { return }
                
                if self.activeAlerts.contains(where: { $0.id == alert.id }) {
                    print("🗑️ [WaitingBus] 公車已到站，自動移除提醒: \(alert.routeName) - \(alert.stopName)")
                    self.removeWaitingAlert(alert)
                }
            }
        }
    }
    
    // MARK: - 提醒觸發（使用統一音頻服務）
    
    private func triggerBusApproachingAlert(alert: WaitingBusAlert, minutesToArrival: Int) {
        let message = "注意！\(alert.routeName) 還有 \(minutesToArrival) 分鐘到達 \(alert.stopName)，請準備前往站牌"
        
        // 使用等車提醒專用的語音播報（最高優先級）
        audioService.announceWaitingBusAlert(message)
        
        // 發送推播通知
        sendNotification(
            title: "🚌 公車即將到站",
            body: "\(alert.routeName) 還有 \(minutesToArrival) 分鐘到達 \(alert.stopName)"
        )
        
        print("🔔 [WaitingBus] 觸發接近提醒: \(alert.routeName) - \(minutesToArrival)分鐘")
    }

    private func triggerBusArrivedAlert(alert: WaitingBusAlert) {
        let message = "緊急提醒！\(alert.routeName) 已到達 \(alert.stopName)，請立即前往搭車"
        
        // 使用等車提醒專用的語音播報（最高優先級）
        audioService.announceWaitingBusAlert(message)
        
        // 發送推播通知
        sendNotification(
            title: "🚨 公車已到站",
            body: "\(alert.routeName) 已到達 \(alert.stopName)，請立即前往搭車"
        )
        
        print("🚨 [WaitingBus] 觸發到站提醒: \(alert.routeName)")
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .defaultCritical  // 使用重要提醒音
        content.badge = 1
        content.categoryIdentifier = "BUS_ALERT"
        
        let request = UNNotificationRequest(
            identifier: "waiting_bus_\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ [WaitingBus] 發送通知失敗: \(error.localizedDescription)")
            } else {
                print("✅ [WaitingBus] 通知發送成功")
            }
        }
    }
    
    // MARK: - 輔助方法
    
    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        
        // 每60秒檢查一次（合理的頻率）
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkArrivalTimes()
        }
        
        // 立即執行一次
        checkArrivalTimes()
        
        print("⏰ [WaitingBus] 開始定期檢查（每60秒）")
    }
    
    private func extractRouteID(from routeName: String) -> String {
        // 如果路線名稱包含城市前綴，去除它
        let cleanName = routeName.replacingOccurrences(of: "台北", with: "")
            .replacingOccurrences(of: "新北", with: "")
            .replacingOccurrences(of: "桃園", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        return cleanName.isEmpty ? routeName : cleanName
    }
    
    private func determineCityFromRoute(_ routeName: String) -> String {
        // 優先使用用戶選擇的城市
        if let savedCity = UserDefaults.standard.string(forKey: "selectedCity") {
            return savedCity
        }
        
        // 根據路線名稱推測（備用邏輯）
        if routeName.contains("紅") || routeName.contains("藍") || routeName.contains("綠") {
            return "Taipei"
        } else if routeName.hasPrefix("9") || routeName == "701" {
            return "NewTaipei"
        }
        
        return "Taipei" // 預設
    }
    
    private func saveActiveAlerts() {
        if let data = try? JSONEncoder().encode(activeAlerts) {
            UserDefaults.standard.set(data, forKey: "activeWaitingAlerts")
            print("💾 [WaitingBus] 已保存 \(activeAlerts.count) 個等車提醒")
        }
    }
    
    private func loadActiveAlerts() {
        guard let data = UserDefaults.standard.data(forKey: "activeWaitingAlerts"),
              let alerts = try? JSONDecoder().decode([WaitingBusAlert].self, from: data) else {
            print("📝 [WaitingBus] 無已保存的等車提醒")
            return
        }
        
        // 只載入仍然有效的提醒
        activeAlerts = alerts.filter { $0.isActive }
        
        if activeAlerts.count != alerts.count {
            saveActiveAlerts() // 清理過期提醒
        }
        
        print("📋 [WaitingBus] 載入了 \(activeAlerts.count) 個等車提醒")
    }
    
    // MARK: - 公開方法
    
    func clearAllAlerts() {
        let count = activeAlerts.count
        activeAlerts.removeAll()
        notifiedAlerts.removeAll()
        saveActiveAlerts()
        
        if count > 0 {
            let message = "已清除所有等車提醒"
            // 改用等車提醒的播報邏輯
            audioService.announceWaitingBusAlert(message)
        }
        
        print("🧹 [WaitingBus] 已清除所有等車提醒")
    }
    
    func pauseChecking() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        print("⏸️ [WaitingBus] 已暫停檢查")
    }
    
    func resumeChecking() {
        startRefreshTimer()
        print("▶️ [WaitingBus] 已恢復檢查")
    }
    
    deinit {
        refreshTimer?.invalidate()
        print("🗑️ [WaitingBus] WaitingBusService 已清理")
    }
}
