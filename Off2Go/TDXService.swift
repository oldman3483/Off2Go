//
//  TDXService.swift
//  Off2Go
//
//  Created by Heidie Lee on 2025/5/15.
//  修復版本：改善站點和到站時間資料獲取
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
    
    // 請求頻率控制
    private var lastRequestTime: Date?
    private let minimumRequestInterval: TimeInterval = 3.0
    private var requestQueue = DispatchQueue(label: "TDXRequestQueue", qos: .userInitiated)

    private init() {
        refreshAccessToken()
    }
    
    // 請求計數器（避免超過每分鐘20次）
    private var requestTimes: [Date] = []
    private let maxRequestsPerMinute = 18 // 設為18次，留點緩衝
    
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
    
    // MARK: - 核心請求方法
       
       private func performThrottledRequest<T: Decodable>(url: URL, completion: @escaping (T?, Error?) -> Void) {
           requestQueue.async { [weak self] in
               guard let self = self else { return }
               
               // 清理一分鐘前的請求記錄
               let oneMinuteAgo = Date().addingTimeInterval(-60)
               self.requestTimes = self.requestTimes.filter { $0 > oneMinuteAgo }
               
               // 檢查是否超過每分鐘限制
               if self.requestTimes.count >= self.maxRequestsPerMinute {
                   let waitTime = 60 - Date().timeIntervalSince(self.requestTimes.first!)
                   print("⏳ [TDX] 每分鐘請求限制，等待 \(Int(waitTime)) 秒")
                   Thread.sleep(forTimeInterval: waitTime + 1)
                   
                   // 重新清理
                   let newOneMinuteAgo = Date().addingTimeInterval(-60)
                   self.requestTimes = self.requestTimes.filter { $0 > newOneMinuteAgo }
               }
               
               // 檢查請求間隔
               let now = Date()
               if let lastRequest = self.lastRequestTime {
                   let timeSinceLastRequest = now.timeIntervalSince(lastRequest)
                   if timeSinceLastRequest < self.minimumRequestInterval {
                       let waitTime = self.minimumRequestInterval - timeSinceLastRequest
                       print("⏳ [TDX] 請求間隔控制，等待 \(waitTime) 秒")
                       Thread.sleep(forTimeInterval: waitTime)
                   }
               }
               
               // 記錄請求時間
               self.requestTimes.append(Date())
               self.lastRequestTime = Date()
               
               DispatchQueue.main.async {
                   self.performRequestWithRetry(url: url, retryCount: 0, completion: completion)
               }
           }
       }
       
       private func performRequestWithRetry<T: Decodable>(url: URL, retryCount: Int, completion: @escaping (T?, Error?) -> Void) {
           DispatchQueue.main.async {
               self.isLoading = true
               if retryCount == 0 {
                   self.errorMessage = nil
               }
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
                       self?.handleRequestError(url: url, retryCount: retryCount, error: error, completion: completion)
                       return
                   }
                   
                   guard let httpResponse = response as? HTTPURLResponse else {
                       print("❌ [TDX] 無效的HTTP回應")
                       completion(nil, NSError(domain: "TDX", code: -3, userInfo: [NSLocalizedDescriptionKey: "無效的伺服器回應"]))
                       return
                   }
                   
                   print("📡 [TDX] HTTP狀態碼: \(httpResponse.statusCode)")
                   
                   // 處理特定狀態碼
                   switch httpResponse.statusCode {
                   case 200...299:
                       // 成功處理
                       self?.handleSuccessResponse(data: data, completion: completion)
                       
                   case 429:
                       print("⚠️ [TDX] 請求頻率過高 (429)，等待後重試")
                       if retryCount < 3 {
                           let waitTime = pow(2.0, Double(retryCount + 1)) // 指數退避：2, 4, 8 秒
                           DispatchQueue.main.asyncAfter(deadline: .now() + waitTime) {
                               self?.performRequestWithRetry(url: url, retryCount: retryCount + 1, completion: completion)
                           }
                       } else {
                           DispatchQueue.main.async {
                               self?.errorMessage = "請求頻率過高，請稍後再試"
                           }
                           completion(nil, NSError(domain: "TDX", code: 429, userInfo: [NSLocalizedDescriptionKey: "請求頻率過高，請稍後再試"]))
                       }
                       
                   case 401:
                       print("⚠️ [TDX] Token 過期 (401)，重新獲取")
                       self?.accessToken = nil
                       self?.tokenExpiration = nil
                       if retryCount < 2 {
                           self?.performRequestWithRetry(url: url, retryCount: retryCount + 1, completion: completion)
                       } else {
                           DispatchQueue.main.async {
                               self?.errorMessage = "身份驗證失敗"
                           }
                           completion(nil, NSError(domain: "TDX", code: 401, userInfo: [NSLocalizedDescriptionKey: "身份驗證失敗"]))
                       }
                       
                   default:
                       let errorMsg = "伺服器錯誤 (\(httpResponse.statusCode))"
                       print("❌ [TDX] \(errorMsg)")
                       DispatchQueue.main.async {
                           self?.errorMessage = errorMsg
                       }
                       completion(nil, NSError(domain: "TDX", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg]))
                   }
               }.resume()
           }
       }
       
       private func handleRequestError<T: Decodable>(url: URL, retryCount: Int, error: Error, completion: @escaping (T?, Error?) -> Void) {
           if retryCount < 2 {
               let waitTime = Double(retryCount + 1) * 2.0 // 2, 4 秒
               print("🔄 [TDX] 網路錯誤重試 (\(retryCount + 1)/2)，等待 \(waitTime) 秒")
               DispatchQueue.main.asyncAfter(deadline: .now() + waitTime) {
                   self.performRequestWithRetry(url: url, retryCount: retryCount + 1, completion: completion)
               }
           } else {
               DispatchQueue.main.async {
                   self.errorMessage = "網路連線失敗"
               }
               completion(nil, error)
           }
       }
       
       private func handleSuccessResponse<T: Decodable>(data: Data?, completion: @escaping (T?, Error?) -> Void) {
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
                   print("📄 [TDX] 回應內容: \(jsonString.prefix(500))")
               }
               DispatchQueue.main.async {
                   self.errorMessage = "數據解析失敗"
               }
               completion(nil, error)
           }
       }
       
       // MARK: - 主要 API 方法
       
       func getAllRoutes(city: String, completion: @escaping ([BusRoute]?, Error?) -> Void) {
           let urlString = "\(baseURL)/Route/City/\(city)?$format=JSON&$top=500"
           
           print("🚌 [TDX] 獲取路線列表: \(city)")
           
           guard let url = URL(string: urlString) else {
               let error = NSError(domain: "TDX", code: -1, userInfo: [NSLocalizedDescriptionKey: "無效 URL"])
               completion(nil, error)
               return
           }
           
           performThrottledRequest(url: url) { (result: [BusRoute]?, error) in
               // 為每個路線加入城市資訊
               if var routes = result {
                   for i in 0..<routes.count {
                       routes[i].city = city  // 設定城市
                   }
                   
                   // 建立路線名稱快取
                   for route in routes {
                       self.routeNameCache[route.RouteID] = route.RouteName.Zh_tw
                   }
                   print("📋 [TDX] 已快取 \(routes.count) 個路線名稱，城市: \(city)")
                   completion(routes, error)
               } else {
                   completion(result, error)
               }
           }
       }
       
       func getStops(city: String, routeName: String, completion: @escaping ([BusStop]?, Error?) -> Void) {
           print("🛑 [TDX] === 獲取站點資料 ===")
           print("   城市: \(city)")
           print("   路線ID: \(routeName)")
           
           // 嘗試多種方法獲取站點
           tryGetStopsMethod1(city: city, routeName: routeName, completion: completion)
       }
       
       // 方法1：使用 DisplayStopOfRoute API - 修改版
    private func tryGetStopsMethod1(city: String, routeName: String, completion: @escaping ([BusStop]?, Error?) -> Void) {
        // 移除 $orderby 參數，因為某些端點不支援
        let urlString = "\(baseURL)/DisplayStopOfRoute/City/\(city)/\(routeName)?$format=JSON"
        
        guard let url = URL(string: urlString) else {
            tryGetStopsMethod2(city: city, routeName: routeName, completion: completion)
            return
        }
        
        print("🔍 [TDX] 方法1 - DisplayStopOfRoute: \(urlString)")
        
        performThrottledRequest(url: url) { (result: [BusStop]?, error: Error?) in
            if let error = error {
                print("❌ [TDX] 方法1失敗: \(error.localizedDescription)")
                self.tryGetStopsMethod2(city: city, routeName: routeName, completion: completion)
            } else if let stops = result, !stops.isEmpty {
                print("✅ [TDX] 方法1成功！獲得 \(stops.count) 條路線的站點")
                self.logStopsDetails(stops)
                // 驗證是否有雙向資料
                self.validateDirectionData(stops)
                completion(stops, nil)
            } else {
                print("⚠️ [TDX] 方法1無資料，嘗試方法2")
                self.tryGetStopsMethod2(city: city, routeName: routeName, completion: completion)
            }
        }
    }
       
       // 方法2：使用 StopOfRoute API
    private func tryGetStopsMethod2(city: String, routeName: String, completion: @escaping ([BusStop]?, Error?) -> Void) {
        let urlString = "\(baseURL)/StopOfRoute/City/\(city)/\(routeName)?$format=JSON"
        
        guard let url = URL(string: urlString) else {
            tryGetStopsMethod3(city: city, routeName: routeName, completion: completion)
            return
        }
        
        print("🔍 [TDX] 方法2 - StopOfRoute: \(urlString)")
        
        performThrottledRequest(url: url) { (result: [BusStop]?, error: Error?) in
            if let error = error {
                print("❌ [TDX] 方法2失敗: \(error.localizedDescription)")
                self.tryGetStopsMethod3(city: city, routeName: routeName, completion: completion)
            } else if let stops = result, !stops.isEmpty {
                print("✅ [TDX] 方法2成功！獲得 \(stops.count) 條路線的站點")
                self.logStopsDetails(stops)
                self.validateDirectionData(stops)
                completion(stops, nil)
            } else {
                print("⚠️ [TDX] 方法2無資料，嘗試方法3")
                self.tryGetStopsMethod3(city: city, routeName: routeName, completion: completion)
            }
        }
    }
       
       // 方法3：使用過濾器
    private func tryGetStopsMethod3(city: String, routeName: String, completion: @escaping ([BusStop]?, Error?) -> Void) {
        let urlString = "\(baseURL)/DisplayStopOfRoute/City/\(city)?$filter=RouteID eq '\(routeName)'&$format=JSON"
        
        guard let url = URL(string: urlString) else {
            print("❌ [TDX] 所有方法都失敗")
            completion([], NSError(domain: "TDX", code: -1, userInfo: [NSLocalizedDescriptionKey: "所有API方法都失敗"]))
            return
        }
        
        print("🔍 [TDX] 方法3 - 使用過濾器: \(urlString)")
        
        performThrottledRequest(url: url) { (result: [BusStop]?, error: Error?) in
            if let stops = result, !stops.isEmpty {
                print("✅ [TDX] 方法3成功！獲得 \(stops.count) 條路線的站點")
                self.logStopsDetails(stops)
                self.validateDirectionData(stops)
                completion(stops, nil)
            } else {
                print("❌ [TDX] 所有方法都無法獲取站點資料")
                completion([], NSError(domain: "TDX", code: -404, userInfo: [NSLocalizedDescriptionKey: "找不到該路線的站點資料"]))
            }
        }
    }
       
       // 新增：驗證方向資料的方法
       private func validateDirectionData(_ stops: [BusStop]) {
           print("🔍 [TDX] === 驗證路線方向資料 ===")
           
           for (index, busStop) in stops.enumerated() {
               let sortedStops = busStop.Stops.sorted { $0.StopSequence < $1.StopSequence }
               
               print("   路線\(index + 1):")
               print("     RouteID: \(busStop.RouteID)")
               print("     站點數: \(sortedStops.count)")
               
               if !sortedStops.isEmpty {
                   let firstStop = sortedStops[0]
                   let lastStop = sortedStops[sortedStops.count - 1]
                   let sequenceRange = "\(firstStop.StopSequence)~\(lastStop.StopSequence)"
                   
                   print("     序號範圍: \(sequenceRange)")
                   print("     起點: \(firstStop.StopName.Zh_tw)")
                   print("     終點: \(lastStop.StopName.Zh_tw)")
                   
                   // 檢查序號是否連續
                   let sequences = sortedStops.map { $0.StopSequence }
                   let isConsecutive = sequences.enumerated().allSatisfy { index, seq in
                       index == 0 || seq == sequences[index - 1] + 1
                   }
                   print("     序號連續性: \(isConsecutive ? "連續" : "不連續")")
               }
           }
       }
       
       // 詳細記錄站點資訊
       private func logStopsDetails(_ stops: [BusStop]) {
           print("📊 [TDX] === 站點資料詳情 ===")
           for (index, busStop) in stops.enumerated() {
               print("   路線\(index + 1): RouteID=\(busStop.RouteID), 站點數=\(busStop.Stops.count)")
               
               if !busStop.Stops.isEmpty {
                   let sortedStops = busStop.Stops.sorted { $0.StopSequence < $1.StopSequence }
                   let firstStop = sortedStops[0]
                   let lastStop = sortedStops[sortedStops.count - 1]
                   print("     起點: \(firstStop.StopName.Zh_tw) (序號:\(firstStop.StopSequence))")
                   print("     終點: \(lastStop.StopName.Zh_tw) (序號:\(lastStop.StopSequence))")
               }
           }
       }
       
       // MARK: - 到站時間相關方法
       
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
           
           performThrottledRequest(url: url) { (result: [BusRoute]?, error: Error?) in
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
       
       // 修改到站時間獲取方法，確保獲取所有方向的資料
    private func tryEstimatedTimeMethod1(city: String, routeID: String, routeName: String, completion: @escaping ([BusArrival]?, Error?) -> Void) {
        // 移除 $orderby 參數
        let urlString = "\(baseURL)/EstimatedTimeOfArrival/City/\(city)?$filter=RouteName/Zh_tw eq '\(routeName)'&$format=JSON"
        
        print("🔍 [TDX] 方法1 - 路線名稱篩選: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            tryEstimatedTimeMethod2(city: city, routeID: routeID, completion: completion)
            return
        }
        
        performThrottledRequest(url: url) { (result: [BusArrival]?, error: Error?) in
            if let arrivals = result, !arrivals.isEmpty {
                print("✅ [TDX] 方法1成功！獲得 \(arrivals.count) 筆到站資料")
                self.printArrivalSample(arrivals)
                self.validateArrivalDirections(arrivals)
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
        
        performThrottledRequest(url: url) { (result: [BusArrival]?, error: Error?) in
            if let arrivals = result, !arrivals.isEmpty {
                print("✅ [TDX] 方法2成功！獲得 \(arrivals.count) 筆到站資料")
                self.printArrivalSample(arrivals)
                self.validateArrivalDirections(arrivals)
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
        
        performThrottledRequest(url: url) { (result: [BusArrival]?, error: Error?) in
            if let arrivals = result, !arrivals.isEmpty {
                print("✅ [TDX] 方法3成功！獲得 \(arrivals.count) 筆到站資料")
                self.printArrivalSample(arrivals)
                self.validateArrivalDirections(arrivals)
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
        
        performThrottledRequest(url: url) { (result: [BusArrival]?, error: Error?) in
            if let allArrivals = result {
                let filteredArrivals = allArrivals.filter { $0.RouteID == routeID }
                
                if !filteredArrivals.isEmpty {
                    print("✅ [TDX] 方法4成功！從 \(allArrivals.count) 筆中篩選出 \(filteredArrivals.count) 筆")
                    self.printArrivalSample(filteredArrivals)
                    self.validateArrivalDirections(filteredArrivals)
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
       
       // 新增：驗證到站時間的方向分布
       private func validateArrivalDirections(_ arrivals: [BusArrival]) {
           print("🔍 [TDX] === 驗證到站時間方向分布 ===")
           
           let directionGroups = Dictionary(grouping: arrivals) { $0.Direction }
           
           for (direction, dirArrivals) in directionGroups.sorted(by: { $0.key < $1.key }) {
               let directionName = direction == 0 ? "去程" : direction == 1 ? "回程" : "其他(\(direction))"
               print("   \(directionName): \(dirArrivals.count) 筆")
               
               // 檢查時間分布
               let validTimes = dirArrivals.compactMap { $0.EstimateTime }.filter { $0 > 0 }
               let avgTime = validTimes.isEmpty ? 0 : validTimes.reduce(0, +) / validTimes.count
               
               print("     有效時間數: \(validTimes.count)/\(dirArrivals.count)")
               if !validTimes.isEmpty {
                   print("     平均到站時間: \(avgTime/60) 分鐘")
               }
               
               // 顯示前3個站點的時間
               let sampleWithTime = dirArrivals.prefix(3)
               for arrival in sampleWithTime {
                   let timeText = arrival.EstimateTime != nil ? "\(arrival.EstimateTime!/60)分" : arrival.statusDescription
                   print("     - StopID:\(arrival.StopID) → \(timeText)")
               }
           }
       }
       
       // 印出到站資料範例
       private func printArrivalSample(_ arrivals: [BusArrival]) {
           print("📊 [TDX] 到站資料分析:")
           print("   總計: \(arrivals.count) 筆")
           
           // 方向分析
           let directionGroups = Dictionary(grouping: arrivals) { $0.Direction }
           print("   方向分布:")
           for (direction, dirArrivals) in directionGroups.sorted(by: { $0.key < $1.key }) {
               let directionName = direction == 0 ? "去程" : direction == 1 ? "返程" : "其他(\(direction))"
               print("     \(directionName): \(dirArrivals.count) 筆")
               
               // 顯示該方向的前3個站點
               let sampleStops = dirArrivals.prefix(3).map { "StopID:\($0.StopID)" }
               print("       範例: \(sampleStops.joined(separator: ", "))")
           }
       }
       
       // MARK: - 輔助方法
       
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
