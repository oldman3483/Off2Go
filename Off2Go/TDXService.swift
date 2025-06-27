//
//  TDXService.swift
//  Off2Go
//
//  Created by Heidie Lee on 2025/5/15.
//

import Foundation

class TDXService: ObservableObject {
    static let shared = TDXService()
    
    // TDX API 設定
    private let clientID = "heidielee1121-4e31aafc-8a76-488b"
    private let clientSecret = "0e8f1d3c-3086-4484-a0a8-15f71bf212c8"
    private let baseURL = "https://tdx.transportdata.tw/api/basic/v2/Bus"
    private let authURL = "https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token"
    
    // Token管理
    private var accessToken: String?
    private var tokenExpiration: Date?
    
    // 狀態管理
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // 路線名稱快取
    private var routeNameCache: [String: String] = [:]
    
    private init() {
        refreshAccessToken()
    }
    
    // MARK: - 核心修復：多重策略獲取到站時間
    
    func getEstimatedTimeOfArrival(city: String, routeName: String, completion: @escaping ([BusArrival]?, Error?) -> Void) {
        print("⏰ [TDX] 開始獲取到站時間: \(city) - \(routeName)")
        
        // 首先嘗試獲取路線的真實名稱
        getRouteRealName(city: city, routeID: routeName) { [weak self] realName in
            guard let self = self else { return }
            
            let actualRouteName = realName ?? routeName
            print("📝 [TDX] 使用路線名稱: \(actualRouteName)")
            
            // 嘗試多種API方法
            self.tryEstimatedTimeMethod1(city: city, routeID: routeName, routeName: actualRouteName, completion: completion)
        }
    }
    
    // 獲取路線真實名稱
    private func getRouteRealName(city: String, routeID: String, completion: @escaping (String?) -> Void) {
        // 先檢查快取
        if let cached = routeNameCache[routeID] {
            completion(cached)
            return
        }
        
        // 從API獲取
        let urlString = "\(baseURL)/Route/City/\(city)?$filter=RouteID eq '\(routeID)'&$format=JSON"
        
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        performSimpleRequest(url: url) { (result: [BusRoute]?, error: Error?) in
            if let routes = result, let firstRoute = routes.first {
                let realName = firstRoute.RouteName.Zh_tw
                self.routeNameCache[routeID] = realName
                print("✅ [TDX] 快取路線名稱: \(routeID) -> \(realName)")
                completion(realName)
            } else {
                completion(nil)
            }
        }
    }
    
    // 方法1：使用路線名稱篩選
    private func tryEstimatedTimeMethod1(city: String, routeID: String, routeName: String, completion: @escaping ([BusArrival]?, Error?) -> Void) {
        let urlString = "\(baseURL)/EstimatedTimeOfArrival/City/\(city)?$filter=RouteName/Zh_tw eq '\(routeName)'&$format=JSON"
        
        print("🔍 [TDX] 方法1 - 路線名稱篩選: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            tryEstimatedTimeMethod2(city: city, routeID: routeID, completion: completion)
            return
        }
        
        performSimpleRequest(url: url) { (result: [BusArrival]?, error: Error?) in
            if let arrivals = result, !arrivals.isEmpty {
                print("✅ [TDX] 方法1成功！獲得 \(arrivals.count) 筆到站資料")
                self.printArrivalSample(arrivals)
                completion(arrivals, nil)
            } else {
                print("⚠️ [TDX] 方法1無結果，嘗試方法2...")
                self.tryEstimatedTimeMethod2(city: city, routeID: routeID, completion: completion)
            }
        }
    }
    
    // 方法2：使用RouteID篩選
    private func tryEstimatedTimeMethod2(city: String, routeID: String, completion: @escaping ([BusArrival]?, Error?) -> Void) {
        let urlString = "\(baseURL)/EstimatedTimeOfArrival/City/\(city)?$filter=RouteID eq '\(routeID)'&$format=JSON"
        
        print("🔍 [TDX] 方法2 - RouteID篩選: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            tryEstimatedTimeMethod3(city: city, routeID: routeID, completion: completion)
            return
        }
        
        performSimpleRequest(url: url) { (result: [BusArrival]?, error: Error?) in
            if let arrivals = result, !arrivals.isEmpty {
                print("✅ [TDX] 方法2成功！獲得 \(arrivals.count) 筆到站資料")
                self.printArrivalSample(arrivals)
                completion(arrivals, nil)
            } else {
                print("⚠️ [TDX] 方法2無結果，嘗試方法3...")
                self.tryEstimatedTimeMethod3(city: city, routeID: routeID, completion: completion)
            }
        }
    }
    
    // 方法3：直接路徑
    private func tryEstimatedTimeMethod3(city: String, routeID: String, completion: @escaping ([BusArrival]?, Error?) -> Void) {
        let urlString = "\(baseURL)/EstimatedTimeOfArrival/City/\(city)/\(routeID)?$format=JSON"
        
        print("🔍 [TDX] 方法3 - 直接路徑: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            tryEstimatedTimeMethod4(city: city, routeID: routeID, completion: completion)
            return
        }
        
        performSimpleRequest(url: url) { (result: [BusArrival]?, error: Error?) in
            if let arrivals = result, !arrivals.isEmpty {
                print("✅ [TDX] 方法3成功！獲得 \(arrivals.count) 筆到站資料")
                self.printArrivalSample(arrivals)
                completion(arrivals, nil)
            } else {
                print("⚠️ [TDX] 方法3無結果，嘗試方法4...")
                self.tryEstimatedTimeMethod4(city: city, routeID: routeID, completion: completion)
            }
        }
    }
    
    // 方法4：獲取所有資料後篩選（最後手段）
    private func tryEstimatedTimeMethod4(city: String, routeID: String, completion: @escaping ([BusArrival]?, Error?) -> Void) {
        let urlString = "\(baseURL)/EstimatedTimeOfArrival/City/\(city)?$format=JSON&$top=1000"
        
        print("🔍 [TDX] 方法4 - 獲取全部後篩選: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("❌ [TDX] 所有方法都失敗")
            completion([], nil)
            return
        }
        
        performSimpleRequest(url: url) { (result: [BusArrival]?, error: Error?) in
            if let allArrivals = result {
                let filteredArrivals = allArrivals.filter { $0.RouteID == routeID }
                
                if !filteredArrivals.isEmpty {
                    print("✅ [TDX] 方法4成功！從 \(allArrivals.count) 筆中篩選出 \(filteredArrivals.count) 筆")
                    self.printArrivalSample(filteredArrivals)
                    completion(filteredArrivals, nil)
                } else {
                    print("❌ [TDX] 方法4篩選後無結果")
                    let availableRouteIDs = Set(allArrivals.map { $0.RouteID }).prefix(10)
                    print("   可用的RouteID範例: \(availableRouteIDs)")
                    completion([], nil)
                }
            } else {
                print("❌ [TDX] 方法4請求失敗: \(error?.localizedDescription ?? "未知錯誤")")
                completion([], error)
            }
        }
    }
    
    // 印出到站資料範例
    private func printArrivalSample(_ arrivals: [BusArrival]) {
        print("📊 [TDX] 到站資料範例:")
        for (index, arrival) in arrivals.prefix(3).enumerated() {
            print("   \(index + 1). 站點:\(arrival.StopID) 方向:\(arrival.Direction) 時間:\(arrival.arrivalTimeText)")
        }
        if arrivals.count > 3 {
            print("   ... 還有 \(arrivals.count - 3) 筆")
        }
    }
    
    // MARK: - Token管理
    
    private func refreshAccessToken(completion: (() -> Void)? = nil) {
        if let expiration = tokenExpiration, expiration > Date(), accessToken != nil {
            completion?()
            return
        }
        
        print("🔑 [TDX] 開始獲取/刷新 API Token...")
        
        guard let url = URL(string: authURL) else {
            print("❌ [TDX] 無效的認證URL")
            completion?()
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let requestBody = "grant_type=client_credentials&client_id=\(clientID)&client_secret=\(clientSecret)"
        request.httpBody = requestBody.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                print("❌ [TDX] 獲取 API 令牌失敗: \(error?.localizedDescription ?? "未知錯誤")")
                DispatchQueue.main.async {
                    self?.errorMessage = "API 連線失敗"
                }
                completion?()
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let token = json["access_token"] as? String,
                   let expiresIn = json["expires_in"] as? Int {
                    
                    self.accessToken = token
                    self.tokenExpiration = Date().addingTimeInterval(TimeInterval(expiresIn - 60))
                    
                    print("✅ [TDX] 成功獲取 API 令牌，有效期: \(expiresIn) 秒")
                    DispatchQueue.main.async {
                        self.errorMessage = nil
                    }
                    completion?()
                } else {
                    print("❌ [TDX] API 令牌回應格式錯誤")
                    DispatchQueue.main.async {
                        self.errorMessage = "API 驗證失敗"
                    }
                    completion?()
                }
            } catch {
                print("❌ [TDX] 解析 API 令牌失敗: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "API 回應格式錯誤"
                }
                completion?()
            }
        }.resume()
    }
    
    private func getAuthHeader() -> [String: String]? {
        guard let token = accessToken else { return nil }
        return [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
    }
    
    // 簡化的請求方法，避免複雜的重試邏輯
    private func performSimpleRequest<T: Decodable>(url: URL, completion: @escaping (T?, Error?) -> Void) {
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        refreshAccessToken { [weak self] in
            guard let self = self, let headers = self.getAuthHeader() else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.errorMessage = "無法獲取身份驗證令牌"
                }
                completion(nil, NSError(domain: "TDX", code: -1, userInfo: [NSLocalizedDescriptionKey: "無法獲取身份驗證令牌"]))
                return
            }
            
            var request = URLRequest(url: url)
            request.allHTTPHeaderFields = headers
            request.timeoutInterval = 30
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
                
                if let error = error {
                    print("❌ [TDX] 網路錯誤: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self?.errorMessage = "網路連線失敗"
                    }
                    completion(nil, error)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ [TDX] 無效的HTTP回應")
                    completion(nil, NSError(domain: "TDX", code: -3, userInfo: [NSLocalizedDescriptionKey: "無效的伺服器回應"]))
                    return
                }
                
                print("📡 [TDX] HTTP狀態碼: \(httpResponse.statusCode)")
                
                guard 200...299 ~= httpResponse.statusCode else {
                    let errorMsg = "伺服器錯誤 (\(httpResponse.statusCode))"
                    print("❌ [TDX] \(errorMsg)")
                    DispatchQueue.main.async {
                        self?.errorMessage = errorMsg
                    }
                    completion(nil, NSError(domain: "TDX", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg]))
                    return
                }
                
                guard let data = data else {
                    print("❌ [TDX] 無數據返回")
                    completion(nil, NSError(domain: "TDX", code: -2, userInfo: [NSLocalizedDescriptionKey: "無數據返回"]))
                    return
                }
                
                print("📊 [TDX] 收到數據大小: \(data.count) bytes")
                
                do {
                    let decodedData = try JSONDecoder().decode(T.self, from: data)
                    print("✅ [TDX] 數據解析成功")
                    completion(decodedData, nil)
                } catch {
                    print("❌ [TDX] 解析失敗: \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("📄 [TDX] 回應內容: \(jsonString.prefix(200))")
                    }
                    DispatchQueue.main.async {
                        self?.errorMessage = "數據解析失敗"
                    }
                    completion(nil, error)
                }
            }.resume()
        }
    }
    
    // MARK: - 其他原有方法（保持簡化版本）
    
    func getAllRoutes(city: String, completion: @escaping ([BusRoute]?, Error?) -> Void) {
        let urlString = "\(baseURL)/Route/City/\(city)?$format=JSON&$top=500"
        
        print("🚌 [TDX] 獲取路線列表: \(city)")
        
        guard let url = URL(string: urlString) else {
            let error = NSError(domain: "TDX", code: -1, userInfo: [NSLocalizedDescriptionKey: "無效 URL"])
            completion(nil, error)
            return
        }
        
        performSimpleRequest(url: url) { (result: [BusRoute]?, error) in
            // 建立路線名稱快取
            if let routes = result {
                for route in routes {
                    self.routeNameCache[route.RouteID] = route.RouteName.Zh_tw
                }
                print("📋 [TDX] 已快取 \(routes.count) 個路線名稱")
            }
            completion(result, error)
        }
    }
    
    func getStops(city: String, routeName: String, completion: @escaping ([BusStop]?, Error?) -> Void) {
        // 優先使用 DisplayStopOfRoute API，因為它包含方向資訊
        let shouldUseDisplayAPI = ["Taipei", "NewTaipei", "Taoyuan", "Taichung"].contains(city)
        let apiEndpoint = shouldUseDisplayAPI ? "DisplayStopOfRoute" : "StopOfRoute"
        
        let urlString = "\(baseURL)/\(apiEndpoint)/City/\(city)?$filter=RouteID eq '\(routeName)'&$format=JSON"
        
        print("🛑 [TDX] 獲取站點資料:")
        print("   城市: \(city)")
        print("   路線: \(routeName)")
        print("   端點: \(apiEndpoint)")
        print("   URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            let error = NSError(domain: "TDX", code: -1, userInfo: [NSLocalizedDescriptionKey: "無效的API URL"])
            completion(nil, error)
            return
        }
        
        performSimpleRequest(url: url) { (result: [BusStop]?, error: Error?) in
            if let error = error {
                print("❌ [TDX] 主要API請求失敗: \(error.localizedDescription)")
                self.getStopsWithoutFilter(city: city, routeName: routeName, completion: completion)
            } else if let stops = result, !stops.isEmpty {
                print("✅ [TDX] 主要API請求成功，回傳路線數: \(stops.count)")
                
                // 檢查每個路線的站點數量和方向資訊
                for (index, busStop) in stops.enumerated() {
                    print("   路線\(index + 1): \(busStop.RouteID) - \(busStop.Stops.count) 個站點")
                    
                    // 檢查是否有不同方向的站點
                    let directions = Set(busStop.Stops.map { _ in 0 }) // 簡化處理，實際可能需要根據API回傳調整
                    print("   包含方向: \(directions)")
                }
                
                completion(stops, nil)
            } else {
                print("⚠️ [TDX] filter方式沒有結果，嘗試備用方法")
                self.getStopsWithoutFilter(city: city, routeName: routeName, completion: completion)
            }
        }
    }
    
    private func getStopsWithoutFilter(city: String, routeName: String, completion: @escaping ([BusStop]?, Error?) -> Void) {
        let shouldUseDisplayAPI = ["Taipei", "NewTaipei"].contains(city)
        let apiEndpoint = shouldUseDisplayAPI ? "DisplayStopOfRoute" : "StopOfRoute"
        let urlString = "\(baseURL)/\(apiEndpoint)/City/\(city)/\(routeName)?$format=JSON"
        
        print("🔄 [TDX] 嘗試備用API請求: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            let error = NSError(domain: "TDX", code: -1, userInfo: [NSLocalizedDescriptionKey: "備用API URL無效"])
            completion(nil, error)
            return
        }
        
        performSimpleRequest(url: url, completion: completion)
    }
    
    func testRouteAvailability(city: String, routeName: String, completion: @escaping (Bool, String) -> Void) {
        let urlString = "\(baseURL)/Route/City/\(city)?$filter=RouteID eq '\(routeName)'&$format=JSON"
        
        print("🔍 [TDX] 測試路線可用性: \(city) - \(routeName)")
        
        guard let url = URL(string: urlString) else {
            completion(false, "URL構建失敗")
            return
        }
        
        performSimpleRequest(url: url) { (result: [BusRoute]?, error: Error?) in
            if let error = error {
                print("❌ [TDX] 路線測試失敗: \(error.localizedDescription)")
                completion(false, "API錯誤: \(error.localizedDescription)")
            } else if let routes = result, !routes.isEmpty {
                print("✅ [TDX] 路線存在，共\(routes.count)筆")
                completion(true, "路線存在，共\(routes.count)筆")
            } else {
                print("⚠️ [TDX] 路線不存在或無資料")
                completion(false, "路線不存在或無資料")
            }
        }
    }
    
    func testConnection(completion: @escaping (Bool) -> Void) {
        print("🔧 [TDX] 測試API連線...")
        getAllRoutes(city: "Taipei") { routes, error in
            let success = error == nil && routes != nil
            print("\(success ? "✅" : "❌") [TDX] API連線測試\(success ? "成功" : "失敗")")
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    func resetError() {
        DispatchQueue.main.async {
            self.errorMessage = nil
        }
    }
    
    func forceRefreshToken(completion: @escaping (Bool) -> Void) {
        accessToken = nil
        tokenExpiration = nil
        
        refreshAccessToken {
            let success = self.accessToken != nil
            completion(success)
        }
    }
}
