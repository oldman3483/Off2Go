//
//  NearbyStopsService.swift
//  Off2Go
//
//  Created by Heidie Lee on 2025/5/27.
//

import Foundation
import CoreLocation
import Combine

class NearbyStopsService: ObservableObject {
    private let tdxService = TDXService.shared
    private let maxDistance: Double = 500 // 最大搜尋距離（公尺）
    private let maxStops: Int = 5 // 最多返回站點數
    
    @Published var isLoading = false
    @Published var nearbyStops: [NearbyStopInfo] = []
    @Published var errorMessage: String?
    
    // 找尋附近站點
    func findNearbyStops(location: CLLocation, completion: @escaping ([NearbyStopInfo]) -> Void) {
        isLoading = true
        errorMessage = nil
        
        // 首先獲取附近的所有路線
        findNearbyRoutes(location: location) { [weak self] routes in
            guard let self = self else { return }
            
            var allStops: [NearbyStopInfo] = []
            let dispatchGroup = DispatchGroup()
            
            // 為每個路線獲取站點資訊
            for route in routes.prefix(10) { // 限制查詢路線數量避免過多 API 呼叫
                dispatchGroup.enter()
                
                self.getStopsForRoute(route: route, userLocation: location) { stops in
                    allStops.append(contentsOf: stops)
                    dispatchGroup.leave()
                }
            }
            
            dispatchGroup.notify(queue: .main) {
                // 按距離排序並去重
                let uniqueStops = self.removeDuplicateStops(allStops)
                let sortedStops = uniqueStops.sorted { $0.distance < $1.distance }
                let finalStops = Array(sortedStops.prefix(self.maxStops))
                
                self.isLoading = false
                self.nearbyStops = finalStops
                completion(finalStops)
            }
        }
    }
    
    // 找尋附近路線
    private func findNearbyRoutes(location: CLLocation, completion: @escaping ([BusRoute]) -> Void) {
        // 根據位置判斷城市（簡化版本，實際應用中可能需要更精確的判斷）
        let city = determineCityFromLocation(location)
        
        tdxService.getAllRoutes(city: city) { routes, error in
            if let error = error {
                print("獲取路線失敗: \(error.localizedDescription)")
                completion([])
                return
            }
            
            completion(routes ?? [])
        }
    }
    
    // 獲取特定路線的站點
    private func getStopsForRoute(route: BusRoute, userLocation: CLLocation, completion: @escaping ([NearbyStopInfo]) -> Void) {
        let city = determineCityFromLocation(userLocation)
        
        tdxService.getStops(city: city, routeName: route.RouteID) { busStops, error in
            if let error = error {
                print("獲取站點失敗: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let busStops = busStops,
                  let busStop = busStops.first(where: { $0.RouteID == route.RouteID }) else {
                completion([])
                return
            }
            
            var nearbyStops: [NearbyStopInfo] = []
            
            // 檢查每個站點的距離
            for stop in busStop.Stops {
                let stopLocation = CLLocation(
                    latitude: stop.StopPosition.PositionLat,
                    longitude: stop.StopPosition.PositionLon
                )
                
                let distance = userLocation.distance(from: stopLocation)
                
                if distance <= self.maxDistance {
                    // 查找該站點是否已存在
                    if let existingIndex = nearbyStops.firstIndex(where: { $0.stopName == stop.StopName.Zh_tw }) {
                        // 添加路線到現有站點
                        let newRoute = RouteInfo(
                            routeName: route.RouteName.Zh_tw,
                            destination: route.DestinationStopNameZh ?? "未知目的地",
                            arrivalTime: "查詢中...",
                            direction: 0
                        )
                        nearbyStops[existingIndex] = NearbyStopInfo(
                            stopName: nearbyStops[existingIndex].stopName,
                            distance: min(nearbyStops[existingIndex].distance, distance),
                            routes: nearbyStops[existingIndex].routes + [newRoute],
                            coordinate: nearbyStops[existingIndex].coordinate
                        )
                    } else {
                        // 創建新的附近站點
                        let routeInfo = RouteInfo(
                            routeName: route.RouteName.Zh_tw,
                            destination: route.DestinationStopNameZh ?? "未知目的地",
                            arrivalTime: "查詢中...",
                            direction: 0
                        )
                        
                        let nearbyStop = NearbyStopInfo(
                            stopName: stop.StopName.Zh_tw,
                            distance: distance,
                            routes: [routeInfo],
                            coordinate: stop.StopPosition.coordinate
                        )
                        
                        nearbyStops.append(nearbyStop)
                    }
                }
            }
            
            completion(nearbyStops)
        }
    }
    
    // 根據位置判斷城市
    private func determineCityFromLocation(_ location: CLLocation) -> String {
        // 簡化的城市判斷邏輯
        // 實際應用中應該使用更精確的地理編碼
        let coordinate = location.coordinate
        
        // 台北市範圍 (大約)
        if coordinate.latitude >= 25.0 && coordinate.latitude <= 25.2 &&
           coordinate.longitude >= 121.4 && coordinate.longitude <= 121.7 {
            return "Taipei"
        }
        
        // 新北市範圍 (大約)
        if coordinate.latitude >= 24.8 && coordinate.latitude <= 25.3 &&
           coordinate.longitude >= 121.2 && coordinate.longitude <= 122.0 {
            return "NewTaipei"
        }
        
        // 桃園市範圍 (大約)
        if coordinate.latitude >= 24.8 && coordinate.latitude <= 25.1 &&
           coordinate.longitude >= 121.1 && coordinate.longitude <= 121.5 {
            return "Taoyuan"
        }
        
        // 預設返回台北
        return "Taipei"
    }
    
    // 去除重複站點
    private func removeDuplicateStops(_ stops: [NearbyStopInfo]) -> [NearbyStopInfo] {
        var uniqueStops: [String: NearbyStopInfo] = [:]
        
        for stop in stops {
            if let existing = uniqueStops[stop.stopName] {
                // 合併路線資訊，保持較短的距離
                let mergedRoutes = existing.routes + stop.routes
                let uniqueRoutes = Array(Set(mergedRoutes.map { $0.routeName })).compactMap { routeName in
                    mergedRoutes.first { $0.routeName == routeName }
                }
                
                uniqueStops[stop.stopName] = NearbyStopInfo(
                    stopName: stop.stopName,
                    distance: min(existing.distance, stop.distance),
                    routes: uniqueRoutes,
                    coordinate: existing.coordinate ?? stop.coordinate
                )
            } else {
                uniqueStops[stop.stopName] = stop
            }
        }
        
        return Array(uniqueStops.values)
    }
    
    // 更新特定站點的到站時間
    func updateArrivalTimes(for stops: [NearbyStopInfo], completion: @escaping ([NearbyStopInfo]) -> Void) {
        var updatedStops = stops
        let dispatchGroup = DispatchGroup()
        
        for (stopIndex, stop) in stops.enumerated() {
            for (routeIndex, route) in stop.routes.enumerated() {
                dispatchGroup.enter()
                
                let city = "Taipei" // 這裡應該根據實際情況確定
                tdxService.getEstimatedTimeOfArrival(city: city, routeName: route.routeName) { arrivals, error in
                    defer { dispatchGroup.leave() }
                    
                    if let error = error {
                        print("獲取到站時間失敗: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let arrivals = arrivals else { return }
                    
                    // 查找對應的到站資訊
                    if let arrival = arrivals.first(where: { arrival in
                        // 這裡需要根據站點名稱或 ID 匹配
                        return true // 簡化處理
                    }) {
                        var updatedRoute = route
                        updatedRoute = RouteInfo(
                            routeName: route.routeName,
                            destination: route.destination,
                            arrivalTime: arrival.arrivalTimeText,
                            direction: route.direction
                        )
                        
                        updatedStops[stopIndex] = NearbyStopInfo(
                            stopName: stop.stopName,
                            distance: stop.distance,
                            routes: updatedStops[stopIndex].routes.enumerated().map { index, r in
                                index == routeIndex ? updatedRoute : r
                            },
                            coordinate: stop.coordinate
                        )
                    }
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            completion(updatedStops)
        }
    }
    
    // 清除快取
    func clearCache() {
        nearbyStops.removeAll()
        errorMessage = nil
    }
    
    // 手動刷新
    func refresh(at location: CLLocation) {
        findNearbyStops(location: location) { _ in
            // 完成後自動更新發布的變數
        }
    }
}
