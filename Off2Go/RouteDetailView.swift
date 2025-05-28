//
//  RouteDetailView.swift
//  BusNotify
//
//  Created by Heidie Lee on 2025/5/15.
//

import SwiftUI
import CoreLocation
import UserNotifications
import Combine

struct RouteDetailView: View {
    let route: BusRoute
    @State private var selectedDirection = 0
    @StateObject private var monitoringService = StationMonitoringService()
    
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var audioService: AudioNotificationService
    
    @State private var showingLocationAlert = false
    @State private var nearestStopIndex: Int?
    @State private var showingAudioSettings = false
    @State private var showingDestinationPicker = false
    @State private var permissionCheckInProgress = false
    @State private var cancellables = Set<AnyCancellable>()
    
    // 權限狀態追蹤
    @State private var lastPermissionCheck: Date?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 路線信息卡片
                routeInfoCard
                
                // 方向選擇
                directionSelector
                
                // 音頻設定快速存取
                audioControlCard
                
                // 監控狀態卡片
                if monitoringService.isMonitoring {
                    monitoringStatusCard
                }
                
                // 站點列表
                stopsListView
                
                // 監控按鈕
                monitoringButton
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(route.RouteName.Zh_tw)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingAudioSettings = true
                }) {
                    Image(systemName: audioService.isAudioEnabled ? "speaker.wave.2" : "speaker.slash")
                        .foregroundColor(audioService.isAudioEnabled ? .blue : .gray)
                }
            }
        }
        .sheet(isPresented: $showingAudioSettings) {
            AudioSettingsView()
        }
        .sheet(isPresented: $showingDestinationPicker) {
            DestinationPickerView(
                stops: monitoringService.stops,
                selectedStopName: Binding(
                    get: { audioService.targetStopName ?? "" },
                    set: { newValue in
                        if !newValue.isEmpty {
                            monitoringService.setDestinationStop(newValue)
                        }
                    }
                )
            )
        }
        .onAppear {
            monitoringService.setRoute(route, direction: selectedDirection)
            updateNearestStop()
            setupPermissionMonitoring()
        }
        .onChange(of: selectedDirection) { newDirection in
            monitoringService.setRoute(route, direction: newDirection)
            updateNearestStop()
        }
        .onChange(of: locationService.currentLocation) { _ in
            updateNearestStop()
        }
        .alert("位置權限需求", isPresented: $showingLocationAlert) {
            Button("前往設定") {
                openAppSettings()
            }
            Button("重新檢查") {
                checkPermissionStatusAndRetry()
            }
            Button("取消", role: .cancel) {
                permissionCheckInProgress = false
            }
        } message: {
            let (_, reason) = locationService.checkLocationServiceStatus()
            Text("Off2Go 需要位置權限來監控您的位置並提供到站提醒。\n\n\(reason)")
        }
    }
    
    // MARK: - 設置權限監聽
    
    private func setupPermissionMonitoring() {
        locationService.$authorizationStatus
            .removeDuplicates()
            .sink { status in
                print("🔄 [RouteDetail] 位置權限狀態變化: \(locationService.authorizationStatusString)")
                
                // 如果權限變成可用，自動隱藏警告
                if status == .authorizedWhenInUse || status == .authorizedAlways {
                    showingLocationAlert = false
                    permissionCheckInProgress = false
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 音頻控制卡片
    
    private var audioControlCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundColor(.purple)
                    .font(.title3)
                
                Text("語音提醒")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { audioService.isAudioEnabled },
                    set: { _ in audioService.toggleAudioNotifications() }
                ))
                .labelsHidden()
            }
            
            if audioService.isAudioEnabled {
                VStack(spacing: 8) {
                    // 目的地選擇
                    HStack {
                        Image(systemName: "flag.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        
                        Text("目的地:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let targetStop = audioService.targetStopName {
                            Text(targetStop)
                                .font(.caption)
                                .fontWeight(.medium)
                        } else {
                            Text("未設定")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("選擇") {
                            showingDestinationPicker = true
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(monitoringService.stops.isEmpty)
                    }
                    
                    // 提醒距離
                    HStack {
                        Image(systemName: "location.circle")
                            .foregroundColor(.green)
                            .font(.caption)
                        
                        Text("提前 \(audioService.notificationDistance) 站提醒")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Button("-") {
                                audioService.decreaseNotificationDistance()
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(audioService.notificationDistance <= 1)
                            
                            Button("+") {
                                audioService.increaseNotificationDistance()
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(audioService.notificationDistance >= 5)
                        }
                    }
                    
                    // 耳機狀態
                    HStack {
                        Image(systemName: audioService.isHeadphonesConnected ? "headphones" : "speaker.wave.2")
                            .foregroundColor(audioService.isHeadphonesConnected ? .green : .orange)
                            .font(.caption)
                        
                        Text(audioService.isHeadphonesConnected ? "耳機已連接" : "建議使用耳機")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("設定") {
                            showingAudioSettings = true
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(audioService.isAudioEnabled ? .purple.opacity(0.3) : .gray.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - 權限檢查和監控邏輯
    
    // 重新檢查權限狀態
    private func checkPermissionStatusAndRetry() {
        print("🔄 [RouteDetail] 重新檢查權限狀態")
        
        // 防止頻繁檢查
        let now = Date()
        if let lastCheck = lastPermissionCheck,
           now.timeIntervalSince(lastCheck) < 2.0 {
            print("⚠️ [RouteDetail] 權限檢查過於頻繁，跳過")
            return
        }
        lastPermissionCheck = now
        
        // 更新權限狀態
        locationService.updateAuthorizationStatusSafely()
        
        // 延遲檢查結果
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let (canUse, reason) = self.locationService.checkLocationServiceStatus()
            
            if canUse {
                print("✅ [RouteDetail] 重新檢查成功，開始監控")
                self.startMonitoringDirectly()
            } else {
                print("⚠️ [RouteDetail] 重新檢查後仍無權限: \(reason)")
                // 保持警告顯示
            }
        }
    }
    
    // 開啟應用設定
    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - UI 組件
    
    // 路線信息卡片
    private var routeInfoCard: some View {
        VStack(spacing: 12) {
            HStack {
                // 路線圖標和號碼
                HStack(spacing: 8) {
                    Image(systemName: "bus.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.blue))
                    
                    Text(route.RouteName.Zh_tw)
                        .font(.title)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                // 收藏按鈕
                FavoriteButton(route: route)
            }
            
            // 路線描述
            if let departure = route.DepartureStopNameZh,
               let destination = route.DestinationStopNameZh {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("起點")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(departure)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right.circle")
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("終點")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(destination)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
    
    // 方向選擇器
    private var directionSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.orange)
                Text("選擇方向")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            Picker("方向", selection: $selectedDirection) {
                Text("去程").tag(0)
                Text("回程").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
    }
    
    // 監控狀態卡片
    private var monitoringStatusCard: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "location.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    
                    Text("監控中")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                Text("共 \(monitoringService.stops.count) 個站點")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.green.opacity(0.2)))
                    .foregroundColor(.green)
            }
            
            if let nearestIndex = nearestStopIndex,
               nearestIndex < monitoringService.stops.count {
                let nearestStop = monitoringService.stops[nearestIndex]
                let distance = calculateDistance(to: nearestStop)
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最近站點")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(nearestStop.StopName.Zh_tw)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("距離")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(Int(distance)) 公尺")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(distance < 100 ? .red : .primary)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.green.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.green.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // 站點列表視圖
    private var stopsListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundColor(.purple)
                Text("站點列表")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if !monitoringService.stops.isEmpty {
                    Text("\(monitoringService.stops.count) 站")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.purple.opacity(0.2)))
                        .foregroundColor(.purple)
                }
            }
            
            // 添加錯誤信息顯示
            if let errorMessage = monitoringService.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.orange)
                    
                    Text("載入失敗")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("重新載入") {
                        monitoringService.refreshData()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else if monitoringService.isLoading {
                // 載入中視圖
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                        .scaleEffect(1.2)
                    
                    Text("載入站點中...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("路線: \(route.RouteName.Zh_tw)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if monitoringService.stops.isEmpty {
                // 空狀態視圖
                VStack(spacing: 16) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                    
                    Text("暫無站點資料")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("該路線可能暫時沒有站點資訊")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("重新載入") {
                        monitoringService.setRoute(route, direction: selectedDirection)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                // 站點列表
                LazyVStack(spacing: 8) {
                    ForEach(Array(zip(monitoringService.stops.indices, monitoringService.stops)), id: \.0) { index, stop in
                        StopRowView(
                            stop: stop,
                            index: index,
                            arrival: monitoringService.arrivals[stop.StopID],
                            distance: calculateDistance(to: stop),
                            isNearest: nearestStopIndex == index,
                            isMonitoring: monitoringService.isMonitoring
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
    }
    
    // 監控按鈕
    private var monitoringButton: some View {
        Button(action: toggleMonitoring) {
            HStack(spacing: 12) {
                if permissionCheckInProgress {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: monitoringService.isMonitoring ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                }
                
                Text(permissionCheckInProgress ? "檢查權限中..." : (monitoringService.isMonitoring ? "停止監控" : "開始監控"))
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(permissionCheckInProgress ? .gray : (monitoringService.isMonitoring ? .red : .blue))
            )
            .foregroundColor(.white)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(monitoringService.stops.isEmpty || permissionCheckInProgress)
    }
    
    // MARK: - 監控控制邏輯
    
    // 切換監控狀態
    private func toggleMonitoring() {
        // 如果正在監控，直接停止
        if monitoringService.isMonitoring {
            print("🛑 [RouteDetail] 停止監控")
            monitoringService.stopMonitoring()
            return
        }
        
        // 如果正在檢查權限，避免重複檢查
        if permissionCheckInProgress {
            print("⚠️ [RouteDetail] 權限檢查進行中，跳過")
            return
        }
        
        print("🔍 [RouteDetail] 準備開始監控...")
        
        // 檢查站點資料
        guard !monitoringService.stops.isEmpty else {
            print("❌ [RouteDetail] 無站點資料")
            monitoringService.refreshData()
            return
        }
        
        // 開始權限檢查流程
        checkPermissionsAndStartMonitoring()
    }
    
    // 權限檢查和監控啟動流程
    private func checkPermissionsAndStartMonitoring() {
        print("🔐 [RouteDetail] 開始權限檢查流程")
        
        // 避免重複檢查
        let now = Date()
        if let lastCheck = lastPermissionCheck,
           now.timeIntervalSince(lastCheck) < 1.0 {
            print("⚠️ [RouteDetail] 權限檢查過於頻繁，跳過")
            return
        }
        
        permissionCheckInProgress = true
        lastPermissionCheck = now
        
        // 直接檢查當前狀態，不要等待更新
        performPermissionCheck()
    }
    
    private func performPermissionCheck() {
        // 直接使用已儲存的權限狀態，不再查詢
        let currentStatus = locationService.authorizationStatus
        let servicesEnabled = CLLocationManager.locationServicesEnabled()
        
        print("🔍 [RouteDetail] 權限狀態檢查:")
        print("   系統位置服務: \(servicesEnabled)")
        print("   授權狀態: \(locationService.statusString(for: currentStatus))")
        
        let canUse = servicesEnabled && (currentStatus == .authorizedWhenInUse || currentStatus == .authorizedAlways)
        
        if canUse {
            print("✅ [RouteDetail] 位置權限正常，開始監控")
            startMonitoringDirectly()
        } else {
            let reason = servicesEnabled ? "位置權限狀態: \(locationService.statusString(for: currentStatus))" : "系統位置服務未開啟"
            handleLocationPermissionIssue(reason: reason, status: currentStatus)
        }
    }
    
    // 處理位置權限問題
    private func handleLocationPermissionIssue(reason: String, status: CLAuthorizationStatus) {
        print("⚠️ [RouteDetail] 位置權限問題: \(reason)")
        
        switch status {
        case .notDetermined:
            // 權限未決定，請求權限
            print("🔐 [RouteDetail] 權限未決定，請求權限")
            requestLocationPermissionAndStart()
            
        case .denied, .restricted:
            // 權限被拒絕，顯示設定提示
            print("🚫 [RouteDetail] 權限被拒絕，顯示設定提示")
            permissionCheckInProgress = false
            showingLocationAlert = true
            
        default:
            // 其他情況，也顯示提示
            print("❓ [RouteDetail] 其他權限狀態: \(locationService.statusString(for: status))")
            permissionCheckInProgress = false
            showingLocationAlert = true
        }
    }
    
    // 請求位置權限並開始監控
    private func requestLocationPermissionAndStart() {
        print("🔐 [RouteDetail] 開始請求位置權限...")
        
        locationService.requestLocationPermission { success in
            DispatchQueue.main.async {
                permissionCheckInProgress = false
                
                if success {
                    print("✅ [RouteDetail] 權限獲取成功")
                    // 延遲一點確保權限狀態完全更新
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        startMonitoringDirectly()
                    }
                } else {
                    print("❌ [RouteDetail] 權限獲取失敗")
                    showingLocationAlert = true
                }
            }
        }
    }
    
    // 直接開始監控
    private func startMonitoringDirectly() {
        permissionCheckInProgress = false
        
        // 直接使用已儲存的權限狀態
        let currentStatus = locationService.authorizationStatus
        
        guard currentStatus == .authorizedWhenInUse || currentStatus == .authorizedAlways else {
            print("❌ [RouteDetail] 最終權限檢查失敗: \(locationService.statusString(for: currentStatus))")
            showingLocationAlert = true
            return
        }
        
        guard !monitoringService.stops.isEmpty else {
            print("❌ [RouteDetail] 無站點資料，無法監控")
            return
        }
        
        print("🚀 [RouteDetail] 開始監控")
        monitoringService.startMonitoring()
    }
    
    // MARK: - 輔助方法
    
    // 計算到站點的距離
    private func calculateDistance(to stop: BusStop.Stop) -> Double {
        guard let userLocation = locationService.currentLocation else {
            return Double.infinity
        }
        
        let stopLocation = CLLocation(
            latitude: stop.StopPosition.PositionLat,
            longitude: stop.StopPosition.PositionLon
        )
        
        return userLocation.distance(from: stopLocation)
    }
    
    // 更新最近站點
    private func updateNearestStop() {
        guard !monitoringService.stops.isEmpty,
              let userLocation = locationService.currentLocation else {
            nearestStopIndex = nil
            return
        }
        
        var minDistance = Double.infinity
        var minIndex: Int?
        
        for (index, stop) in monitoringService.stops.enumerated() {
            let distance = calculateDistance(to: stop)
            if distance < minDistance {
                minDistance = distance
                minIndex = index
            }
        }
        
        nearestStopIndex = minIndex
    }
}

// MARK: - 站點行視圖

struct StopRowView: View {
    let stop: BusStop.Stop
    let index: Int
    let arrival: BusArrival?
    let distance: Double
    let isNearest: Bool
    let isMonitoring: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // 站點序號
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(isNearest ? .orange : .gray)
                )
            
            // 站點信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(stop.StopName.Zh_tw)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    if isNearest {
                        Image(systemName: "location.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                // 到站信息
                if let arrival = arrival {
                    Text(arrival.arrivalTimeText)
                        .font(.caption)
                        .foregroundColor(arrival.isComingSoon ? .red : .secondary)
                        .fontWeight(arrival.isComingSoon ? .semibold : .regular)
                } else {
                    Text("無到站資訊")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 距離信息
            VStack(alignment: .trailing, spacing: 4) {
                if distance != Double.infinity {
                    Text(formatDistance(distance))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(distance < 100 ? .red : (distance < 300 ? .orange : .secondary))
                } else {
                    Text("--")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if isMonitoring && distance < 200 {
                    Text("監控中")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.green.opacity(0.2)))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isNearest ? .orange.opacity(0.1) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isNearest ? .orange.opacity(0.3) : .clear, lineWidth: 1)
                )
        )
    }
    
    private func formatDistance(_ distance: Double) -> String {
        if distance < 1000 {
            return "\(Int(distance)) m"
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
}

// MARK: - 收藏按鈕組件

struct FavoriteButton: View {
    let route: BusRoute
    @AppStorage("favoriteRoutes") private var favoriteRoutesData: Data = Data()
    @State private var favoriteRoutes: [BusRoute] = []
    
    private var isFavorite: Bool {
        favoriteRoutes.contains { $0.RouteID == route.RouteID }
    }
    
    var body: some View {
        Button(action: toggleFavorite) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.title3)
                .foregroundColor(isFavorite ? .red : .gray)
        }
        .onAppear {
            loadFavoriteRoutes()
        }
    }
    
    private func loadFavoriteRoutes() {
        if let decoded = try? JSONDecoder().decode([BusRoute].self, from: favoriteRoutesData) {
            favoriteRoutes = decoded
        }
    }
    
    private func toggleFavorite() {
        if favoriteRoutes.contains(where: { $0.RouteID == route.RouteID }) {
            favoriteRoutes.removeAll { $0.RouteID == route.RouteID }
        } else {
            favoriteRoutes.append(route)
        }
        
        if let encoded = try? JSONEncoder().encode(favoriteRoutes) {
            favoriteRoutesData = encoded
        }
    }
}
