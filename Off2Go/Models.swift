//
//  Models.swift
//  BusNotify
//
//  Created by Heidie Lee on 2025/5/15.
//

import Foundation
import CoreLocation

// MARK: - 原有的公車路線模型
struct BusRoute: Codable, Identifiable, Hashable {
    let RouteID: String
    let RouteName: RouteName
    let DepartureStopNameZh: String?
    let DestinationStopNameZh: String?
    
    var city: String?
    
    var id: String { RouteID }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(RouteID)
    }
    
    struct RouteName: Codable, Hashable {
        let Zh_tw: String
        let En: String?
    }
}

// MARK: - 原有的公車站點模型
struct BusStop: Codable, Identifiable {
    let RouteID: String
    let Stops: [Stop]
    
    var id: String { RouteID }
    
    struct Stop: Codable, Identifiable, Hashable {
        let StopID: String
        let StopName: StopName
        let StopPosition: StopPosition
        let StopSequence: Int
        
        var id: String { StopID }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(StopID)
        }
        
        struct StopName: Codable, Hashable {
            let Zh_tw: String
            let En: String?
        }
        
        struct StopPosition: Codable, Hashable {
            let PositionLat: Double
            let PositionLon: Double
            
            var coordinate: CLLocationCoordinate2D {
                return CLLocationCoordinate2D(latitude: PositionLat, longitude: PositionLon)
            }
        }
    }
}

// MARK: - 原有的公車位置模型
struct BusPosition: Codable, Identifiable {
    let PlateNumb: String
    let PositionLat: Double
    let PositionLon: Double
    let Direction: Int
    let Speed: Double?
    
    var id: String { PlateNumb }
    
    var coordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: PositionLat, longitude: PositionLon)
    }
}

// MARK: - 原有的公車到站時間模型
struct BusArrival: Codable, Identifiable {
    let StopID: String
    let RouteID: String
    let Direction: Int
    let EstimateTime: Int?    // 預估到站時間 (秒)
    let StopStatus: Int       // 車輛狀態 (0:正常, 1:尚未發車, 2:交管不停靠, 3:末班車已過, 4:今日未營運)
    
    var id: String { StopID }
    
    var isComingSoon: Bool {
        if let time = EstimateTime {
            return time <= 180 && time > 0 // 3分鐘內到站
        }
        return false
    }
    
    var statusDescription: String {
        switch StopStatus {
        case 0: return "正常"
        case 1: return "尚未發車"
        case 2: return "交管不停靠"
        case 3: return "末班車已過"
        case 4: return "今日未營運"
        default: return "未知狀態"
        }
    }
    
    var arrivalTimeText: String {
        if let time = EstimateTime {
            if time <= 60 {
                return "即將到站"
            } else {
                return "\(time / 60) 分鐘"
            }
        } else {
            return statusDescription
        }
    }
}

// MARK: - 原有的城市模型
struct City: Identifiable {
    let id: String
    let nameZh: String
    let nameEn: String
    
    static let allCities = [
        City(id: "Taipei", nameZh: "台北", nameEn: "Taipei"),
        City(id: "NewTaipei", nameZh: "新北", nameEn: "New Taipei"),
        City(id: "Taoyuan", nameZh: "桃園", nameEn: "Taoyuan"),
        City(id: "Taichung", nameZh: "台中", nameEn: "Taichung"),
        City(id: "Tainan", nameZh: "台南", nameEn: "Tainan"),
        City(id: "Kaohsiung", nameZh: "高雄", nameEn: "Kaohsiung")
    ]
}

// MARK: - 新增：附近站點資訊模型
struct NearbyStopInfo {
    let stopName: String
    let distance: Double // 距離（公尺）
    let routes: [RouteInfo]
    let coordinate: CLLocationCoordinate2D?
    
    // 計算屬性：格式化距離顯示
    var formattedDistance: String {
        if distance < 1000 {
            return "\(Int(distance))m"
        } else {
            return String(format: "%.1fkm", distance / 1000)
        }
    }
    
    // 計算屬性：是否在步行範圍內
    var isWalkingDistance: Bool {
        return distance <= 500 // 500公尺內
    }
}

// MARK: - 新增：路線資訊模型
struct RouteInfo: Hashable {
    let routeName: String
    let destination: String
    let arrivalTime: String
    let direction: Int
    let routeID: String?
    
    // 初始化方法
    init(routeName: String, destination: String, arrivalTime: String, direction: Int, routeID: String? = nil) {
        self.routeName = routeName
        self.destination = destination
        self.arrivalTime = arrivalTime
        self.direction = direction
        self.routeID = routeID
    }
    
    // 計算屬性：是否即將到站
    var isComingSoon: Bool {
        return arrivalTime.contains("即將到站") || arrivalTime.contains("1分") || arrivalTime.contains("2分")
    }
    
    // 計算屬性：路線顏色（根據路線名稱）
    var routeColor: String {
        switch routeName.prefix(1) {
        case "紅": return "red"
        case "藍": return "blue"
        case "綠": return "green"
        case "橘": return "orange"
        case "棕": return "brown"
        case "黃": return "yellow"
        default: return "blue"
        }
    }
    
    // Hashable 實現
    func hash(into hasher: inout Hasher) {
        hasher.combine(routeName)
        hasher.combine(destination)
        hasher.combine(direction)
    }
    
    static func == (lhs: RouteInfo, rhs: RouteInfo) -> Bool {
        return lhs.routeName == rhs.routeName &&
               lhs.destination == rhs.destination &&
               lhs.direction == rhs.direction
    }
}

// MARK: - 新增：音頻通知設定模型
struct AudioNotificationSettings: Codable {
    var isEnabled: Bool = true
    var language: String = "zh-TW"
    var speechRate: Float = 0.5
    var speechVolume: Float = 1.0
    var notificationDistance: Int = 2 // 提前幾站提醒
    var allowSpeakerOutput: Bool = false // 是否允許外放
    
    // 預設設定
    static let `default` = AudioNotificationSettings()
    
    // 從 UserDefaults 載入
    static func load() -> AudioNotificationSettings {
        guard let data = UserDefaults.standard.data(forKey: "AudioNotificationSettings"),
              let settings = try? JSONDecoder().decode(AudioNotificationSettings.self, from: data) else {
            return .default
        }
        return settings
    }
    
    // 保存到 UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "AudioNotificationSettings")
        }
    }
}

// MARK: - 新增：監控狀態模型
struct MonitoringStatus {
    let isActive: Bool
    let startTime: Date?
    let routeName: String?
    let direction: String?
    let destinationStop: String?
    let nearestStopName: String?
    let nearestStopDistance: Double?
    let notifiedStopsCount: Int
    let totalStopsCount: Int
    
    // 計算屬性：監控持續時間
    var duration: TimeInterval {
        guard let startTime = startTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    // 計算屬性：格式化持續時間
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // 計算屬性：進度百分比
    var progressPercentage: Double {
        guard totalStopsCount > 0 else { return 0 }
        return Double(notifiedStopsCount) / Double(totalStopsCount)
    }
}

// MARK: - 新增：搜尋歷史模型
struct SearchHistory: Codable, Identifiable {
    let id = UUID()
    let searchText: String
    let timestamp: Date
    let resultCount: Int
    
    // 計算屬性：格式化時間
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    // 計算屬性：是否為今天
    var isToday: Bool {
        Calendar.current.isDateInToday(timestamp)
    }
}

// MARK: - 新增：搜尋歷史管理器
class SearchHistoryManager {
    private let maxHistoryCount = 20
    private let userDefaultsKey = "SearchHistory"
    
    static let shared = SearchHistoryManager()
    
    private init() {}
    
    // 載入搜尋歷史
    func loadHistory() -> [SearchHistory] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let history = try? JSONDecoder().decode([SearchHistory].self, from: data) else {
            return []
        }
        return history.sorted { $0.timestamp > $1.timestamp }
    }
    
    // 添加搜尋記錄
    func addSearch(_ searchText: String, resultCount: Int) {
        var history = loadHistory()
        
        // 移除重複的搜尋
        history.removeAll { $0.searchText == searchText }
        
        // 添加新搜尋
        let newSearch = SearchHistory(
            searchText: searchText,
            timestamp: Date(),
            resultCount: resultCount
        )
        history.insert(newSearch, at: 0)
        
        // 限制歷史記錄數量
        if history.count > maxHistoryCount {
            history = Array(history.prefix(maxHistoryCount))
        }
        
        // 保存
        saveHistory(history)
    }
    
    // 清除搜尋歷史
    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
    
    // 刪除特定搜尋記錄
    func removeSearch(_ search: SearchHistory) {
        var history = loadHistory()
        history.removeAll { $0.id == search.id }
        saveHistory(history)
    }
    
    // 保存搜尋歷史
    private func saveHistory(_ history: [SearchHistory]) {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}

// MARK: - 新增：應用程式設定模型
struct AppSettings: Codable {
    var selectedCity: String = "Taipei"
    var defaultNotificationDistance: Double = 200.0
    var autoStopMonitoring: Bool = true
    var showEstimatedTime: Bool = true
    var backgroundMonitoring: Bool = true
    var lastUpdateTime: Date?
    
    // 從 UserDefaults 載入
    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: "AppSettings"),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }
    
    // 保存到 UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "AppSettings")
        }
    }
}
