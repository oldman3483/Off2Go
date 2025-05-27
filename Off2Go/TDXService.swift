//
//  TDXService.swift
//  BusNotify
//
//  Created by Heidie Lee on 2025/5/15.
//

import Foundation

class TDXService: ObservableObject {
    // 單例實例
    static let shared = TDXService()
    
    // TDX API 金鑰
    private let clientID = "heidielee1121-4e31aafc-8a76-488b"
    private let clientSecret = "0e8f1d3c-3086-4484-a0a8-15f71bf212c8"
    
    // 基礎 URL
    private let baseURL = "https://tdx.transportdata.tw/api/basic/v2/Bus"
    private let authURL = "https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token"
    
    // 身份驗證令牌
    private var accessToken: String?
    private var tokenExpiration: Date?
    
    // 請求狀態
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // 初始化函數
    private init() {
        // 在初始化時獲取令牌
        refreshAccessToken()
    }
    
    // 獲取或刷新 OAuth 2.0 令牌
    private func refreshAccessToken(completion: (() -> Void)? = nil) {
        // 如果現有令牌仍然有效，直接返回
        if let expiration = tokenExpiration, expiration > Date(), accessToken != nil {
            completion?()
            return
        }
        
        // 準備身份驗證請求
        guard let url = URL(string: authURL) else {
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
                print("獲取 TDX API 令牌失敗: \(error?.localizedDescription ?? "未知錯誤")")
                DispatchQueue.main.async {
                    self?.errorMessage = "API 連線失敗，請檢查網路連線"
                }
                completion?()
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let token = json["access_token"] as? String,
                   let expiresIn = json["expires_in"] as? Int {
                    
                    self.accessToken = token
                    // 設置過期時間（提前 60 秒刷新）
                    self.tokenExpiration = Date().addingTimeInterval(TimeInterval(expiresIn - 60))
                    
                    print("成功獲取 TDX API 令牌")
                    DispatchQueue.main.async {
                        self.errorMessage = nil
                    }
                    completion?()
                } else {
                    DispatchQueue.main.async {
                        self.errorMessage = "API 驗證失敗"
                    }
                    completion?()
                }
            } catch {
                print("解析 TDX API 令牌失敗: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "API 回應格式錯誤"
                }
                completion?()
            }
        }.resume()
    }
    
    // 取得 Bearer Token 認證頭
    private func getAuthHeader() -> [String: String]? {
        guard let token = accessToken else { return nil }
        return [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
    }
    
    // 執行 API 請求
    private func performRequest<T: Decodable>(url: URL, completion: @escaping (T?, Error?) -> Void) {
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        // 確保有有效的令牌
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
                    DispatchQueue.main.async {
                        self?.errorMessage = "網路連線失敗: \(error.localizedDescription)"
                    }
                    completion(nil, error)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "無效的伺服器回應"
                    }
                    completion(nil, NSError(domain: "TDX", code: -3, userInfo: [NSLocalizedDescriptionKey: "無效的伺服器回應"]))
                    return
                }
                
                guard 200...299 ~= httpResponse.statusCode else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "伺服器錯誤 (\(httpResponse.statusCode))"
                    }
                    completion(nil, NSError(domain: "TDX", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]))
                    return
                }
                
                guard let data = data else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "無數據返回"
                    }
                    completion(nil, NSError(domain: "TDX", code: -2, userInfo: [NSLocalizedDescriptionKey: "無數據返回"]))
                    return
                }
                
                do {
                    let decodedData = try JSONDecoder().decode(T.self, from: data)
                    completion(decodedData, nil)
                } catch {
                    print("解析失敗: \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("回應內容: \(jsonString.prefix(500))")
                    }
                    DispatchQueue.main.async {
                        self?.errorMessage = "數據解析失敗"
                    }
                    completion(nil, error)
                }
            }.resume()
        }
    }
    
    // 獲取特定城市的所有公車路線
    func getAllRoutes(city: String, completion: @escaping ([BusRoute]?, Error?) -> Void) {
        let urlString = "\(baseURL)/Route/City/\(city)?$format=JSON&$top=300"
        
        guard let url = URL(string: urlString) else {
            completion(nil, NSError(domain: "TDX", code: -1, userInfo: [NSLocalizedDescriptionKey: "無效 URL"]))
            return
        }
        
        performRequest(url: url, completion: completion)
    }
    
    // 獲取特定路線的所有站點
    func getStops(city: String, routeName: String, completion: @escaping ([BusStop]?, Error?) -> Void) {
        let urlString = "\(baseURL)/StopOfRoute/City/\(city)/\(routeName)?$format=JSON"
        
        guard let encodedString = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encodedString) else {
            completion(nil, NSError(domain: "TDX", code: -1, userInfo: [NSLocalizedDescriptionKey: "無效 URL"]))
            return
        }
        
        performRequest(url: url, completion: completion)
    }
    
    // 獲取特定路線的實時公車位置
    func getBusPositions(city: String, routeName: String, completion: @escaping ([BusPosition]?, Error?) -> Void) {
        let urlString = "\(baseURL)/RealTimeByFrequency/City/\(city)/\(routeName)?$format=JSON"
        
        guard let encodedString = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encodedString) else {
            completion(nil, NSError(domain: "TDX", code: -1, userInfo: [NSLocalizedDescriptionKey: "無效 URL"]))
            return
        }
        
        performRequest(url: url, completion: completion)
    }
    
    // 獲取特定路線的預估到站時間
    func getEstimatedTimeOfArrival(city: String, routeName: String, completion: @escaping ([BusArrival]?, Error?) -> Void) {
        let urlString = "\(baseURL)/EstimatedTimeOfArrival/City/\(city)/\(routeName)?$format=JSON"
        
        guard let encodedString = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encodedString) else {
            completion(nil, NSError(domain: "TDX", code: -1, userInfo: [NSLocalizedDescriptionKey: "無效 URL"]))
            return
        }
        
        performRequest(url: url, completion: completion)
    }
    
    // 測試 API 連線
    func testConnection(completion: @escaping (Bool) -> Void) {
        getAllRoutes(city: "Taipei") { routes, error in
            DispatchQueue.main.async {
                completion(error == nil && routes != nil)
            }
        }
    }
}
