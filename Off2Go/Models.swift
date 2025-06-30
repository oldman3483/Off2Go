//
//  Models.swift
//  Off2Go
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

// MARK: - 等車提醒模型
struct WaitingBusAlert: Codable, Identifiable {
    let id: UUID
    let routeName: String
    let stopName: String
    let stopID: String
    let direction: Int
    let createdTime: Date
    let alertMinutes: Int // 提前幾分鐘提醒
    
    // 主要的初始化方法
    init(routeName: String, stopName: String, stopID: String, direction: Int, alertMinutes: Int) {
        self.id = UUID()
        self.routeName = routeName
        self.stopName = stopName
        self.stopID = stopID
        self.direction = direction
        self.createdTime = Date()
        self.alertMinutes = alertMinutes
    }
    
    var isActive: Bool {
        // 等車提醒有效期限（例如30分鐘）
        Date().timeIntervalSince(createdTime) < 1800
    }
    
    var formattedCreatedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: createdTime)
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
