//
//  Models.swift
//  BusNotify
//
//  Created by Heidie Lee on 2025/5/15.
//

import Foundation
import CoreLocation

// 公車路線模型
struct BusRoute: Codable, Identifiable, Hashable {
    let RouteID: String
    let RouteName: RouteName
    let DepartureStopNameZh: String?
    let DestinationStopNameZh: String?
    
    var id: String { RouteID }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(RouteID)
    }
    
    struct RouteName: Codable, Hashable {
        let Zh_tw: String
        let En: String?
    }
}

// 公車站點模型
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

// 公車位置模型
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

// 公車到站時間模型
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

// 城市模型
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
