//
//  RouteDetailView.swift
//  Off2Go
//
//  Created by Heidie Lee on 2025/5/15.
//  Improved version with better UX
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
    @State private var permissionCheckInProgress = false
    @State private var cancellables = Set<AnyCancellable>()
    
    @State private var selectedStopForAction: BusStop.Stop?
    @State private var showingStopActionSheet = false
    
    // 新增：目的地設定狀態
    @State private var selectedDestinationIndex: Int?
    @State private var showingDestinationHint = false
    
    // 權限狀態追蹤
    @State private var lastPermissionCheck: Date?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 路線信息卡片
                routeInfoCard
                
                // 簡化的方向選擇 - 更直覺的設計
                directionSelectorCard
                
                // 目的地設定狀態卡片
                destinationStatusCard
                
                // 監控狀態卡片
                if monitoringService.isMonitoring {
                    monitoringStatusCard
                }
                
                // 站點列表 - 可直接點選設定目的地
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
                Menu {
                    Button(action: {
                        showingAudioSettings = true
                    }) {
                        Label("音頻設定", systemImage: "speaker.wave.2")
                    }
                    
                    if selectedDestinationIndex != nil {
                        Button(action: {
                            clearDestination()
                        }) {
                            Label("清除目的地", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.blue)
                }
            }
        }
        .sheet(isPresented: $showingAudioSettings) {
            AudioSettingsView()
        }
        .onAppear {
            monitoringService.setRoute(route, direction: selectedDirection)
            updateNearestStop()
            setupPermissionMonitoring()
            
            // 顯示提示
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if selectedDestinationIndex == nil && !monitoringService.stops.isEmpty {
                    showingDestinationHint = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showingDestinationHint = false
                    }
                }
            }
        }
        .onChange(of: selectedDirection) { newDirection in
            monitoringService.setRoute(route, direction: newDirection)
            selectedDestinationIndex = nil // 重置目的地
            audioService.clearDestination()
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
        .sheet(isPresented: $showingStopActionSheet) {
            if let stop = selectedStopForAction,
               let index = monitoringService.stops.firstIndex(where: { $0.StopID == stop.StopID }) {
                StopActionSheet(
                    stop: stop,
                    index: index,
                    route: route,
                    isCurrentDestination: selectedDestinationIndex == index
                ) { action in
                    handleStopAction(action, for: stop, at: index)
                    showingStopActionSheet = false
                }
                .presentationDetents([.height(300), .medium])
                .presentationDragIndicator(.visible)
            }
        }
    }
    
    // MARK: - 新設計的方向選擇卡片
    
    private var directionSelectorCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "arrow.left.arrow.right.circle")
                    .foregroundColor(.blue)
                    .font(.title3)
                
                Text("選擇行駛方向")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            // 更直覺的方向選擇
            HStack(spacing: 12) {
                // 去程
                DirectionButton(
                    title: "去程",
                    subtitle: route.DestinationStopNameZh ?? "往終點",
                    isSelected: selectedDirection == 0,
                    icon: "arrow.right.circle.fill"
                ) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedDirection = 0
                    }
                }
                
                // 回程
                DirectionButton(
                    title: "回程",
                    subtitle: route.DepartureStopNameZh ?? "往起點",
                    isSelected: selectedDirection == 1,
                    icon: "arrow.left.circle.fill"
                ) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedDirection = 1
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
    
    // MARK: 處理動作的方法
    private func handleStopAction(_ action: StopAction, for stop: BusStop.Stop, at index: Int) {
        switch action {
        case .setAsDestination:
            setDestination(index: index)
        case .clearDestination:
            clearDestination()
        case .viewOtherRoutes:
            // TODO: 顯示該站牌的其他路線
            print("🚌 查看 \(stop.StopName.Zh_tw) 的其他路線")
        case .cancel:
            break
        }
    }
    
    // MARK: - 目的地狀態卡片
    
    private var destinationStatusCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "flag.circle.fill")
                    .foregroundColor(selectedDestinationIndex != nil ? .green : .orange)
                    .font(.title3)
                
                Text("目的地設定")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if selectedDestinationIndex != nil {
                    Toggle("語音提醒", isOn: Binding(
                        get: { audioService.isAudioEnabled },
                        set: { _ in audioService.toggleAudioNotifications() }
                    ))
                    .labelsHidden()
                    .scaleEffect(0.8)
                }
            }
            
            if let destinationIndex = selectedDestinationIndex,
               destinationIndex < monitoringService.stops.count {
                let destinationStop = monitoringService.stops[destinationIndex]
                
                HStack {
                    Text(destinationStop.StopName.Zh_tw)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("提前 \(audioService.notificationDistance) 站提醒")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
            } else {
                Text("點擊下方站點設定目的地")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(selectedDestinationIndex != nil ? .green.opacity(0.1) : .orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            selectedDestinationIndex != nil ? .green.opacity(0.3) : .orange.opacity(0.3),
                            lineWidth: 1
                        )
                )
        )
    }
    
    // MARK: - 改進的站點列表（可直接點選設定目的地）
    
    private var stopsListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.circle")
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
            
            if let errorMessage = monitoringService.errorMessage {
                errorView(errorMessage)
            } else if monitoringService.isLoading {
                loadingView
            } else if monitoringService.stops.isEmpty {
                emptyStopsView
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(Array(zip(monitoringService.stops.indices, monitoringService.stops)), id: \.0) { index, stop in
                        StopRowView(
                            stop: stop,
                            index: index,
                            arrival: monitoringService.arrivals[stop.StopID],
                            distance: calculateDistance(to: stop),
                            isNearest: nearestStopIndex == index,
                            isDestination: selectedDestinationIndex == index,
                            isMonitoring: monitoringService.isMonitoring
                        ) {
                            // 點擊顯示動作選單
                            selectedStopForAction = stop
                            showingStopActionSheet = true
                        }
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
    
    // MARK: - 目的地設定相關方法
    
    private func setDestination(index: Int) {
        guard index < monitoringService.stops.count else { return }
        
        let stop = monitoringService.stops[index]
        
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedDestinationIndex = index
        }
        
        // 設定音頻服務目的地
        audioService.setDestination(route.RouteName.Zh_tw, stopName: stop.StopName.Zh_tw)
        monitoringService.setDestinationStop(stop.StopName.Zh_tw)
        
        // 隱藏提示
        showingDestinationHint = false
        
        print("🎯 [RouteDetail] 設定目的地: \(stop.StopName.Zh_tw) (索引: \(index))")
    }
    
    private func clearDestination() {
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedDestinationIndex = nil
        }
        
        audioService.clearDestination()
        monitoringService.clearDestinationStop()
        
        print("🗑️ [RouteDetail] 已清除目的地")
    }
    
    // MARK: - 支援元件和方法（其他部分保持不變，只列出關鍵修改）
    
    // 監控狀態卡片保持不變...
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
    
    // 其他方法保持不變...
    private func setupPermissionMonitoring() {
        locationService.$authorizationStatus
            .removeDuplicates()
            .sink { status in
                print("🔄 [RouteDetail] 位置權限狀態變化: \(locationService.authorizationStatusString)")
                
                if status == .authorizedWhenInUse || status == .authorizedAlways {
                    showingLocationAlert = false
                    permissionCheckInProgress = false
                }
            }
            .store(in: &cancellables)
    }
    
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
    
    // 路線信息卡片保持不變...
    private var routeInfoCard: some View {
        VStack(spacing: 12) {
            HStack {
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
                
                FavoriteButton(route: route)
            }
            
            if let departure = route.DepartureStopNameZh,
               let destination = route.DestinationStopNameZh {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("起點")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(selectedDirection == 0 ? departure : destination)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .animation(.easeInOut(duration: 0.3), value: selectedDirection)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right.circle")
                        .foregroundColor(.blue)
                        .rotationEffect(.degrees(selectedDirection == 0 ? 0 : 180))
                        .animation(.easeInOut(duration: 0.3), value: selectedDirection)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("終點")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(selectedDirection == 0 ? destination : departure)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .animation(.easeInOut(duration: 0.3), value: selectedDirection)
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
    
    // 監控按鈕保持不變...
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
    
    // 錯誤視圖
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundColor(.orange)
            
            Text("載入失敗")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(message)
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
    }
    
    // 載入視圖
    private var loadingView: some View {
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
    }
    
    // 空站點視圖
    private var emptyStopsView: some View {
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
    }
    
    // 監控相關方法保持不變...
    private func toggleMonitoring() {
        if monitoringService.isMonitoring {
            print("🛑 [RouteDetail] 停止監控")
            monitoringService.stopMonitoring()
            return
        }
        
        if permissionCheckInProgress {
            print("⚠️ [RouteDetail] 權限檢查進行中，跳過")
            return
        }
        
        print("🔍 [RouteDetail] 準備開始監控...")
        
        guard !monitoringService.stops.isEmpty else {
            print("❌ [RouteDetail] 無站點資料")
            monitoringService.refreshData()
            return
        }
        
        checkPermissionsAndStartMonitoring()
    }
    
    private func checkPermissionsAndStartMonitoring() {
        print("🔐 [RouteDetail] 開始權限檢查流程")
        
        let now = Date()
        if let lastCheck = lastPermissionCheck,
           now.timeIntervalSince(lastCheck) < 1.0 {
            print("⚠️ [RouteDetail] 權限檢查過於頻繁，跳過")
            return
        }
        
        permissionCheckInProgress = true
        lastPermissionCheck = now
        
        performPermissionCheck()
    }
    
    private func performPermissionCheck() {
        let currentStatus = locationService.authorizationStatus
        let servicesEnabled = locationService.canUseLocationService
        
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
    
    private func handleLocationPermissionIssue(reason: String, status: CLAuthorizationStatus) {
        print("⚠️ [RouteDetail] 位置權限問題: \(reason)")
        
        switch status {
        case .notDetermined:
            print("🔐 [RouteDetail] 權限未決定，請求權限")
            requestLocationPermissionAndStart()
            
        case .denied, .restricted:
            print("🚫 [RouteDetail] 權限被拒絕，顯示設定提示")
            permissionCheckInProgress = false
            showingLocationAlert = true
            
        default:
            print("❓ [RouteDetail] 其他權限狀態: \(locationService.statusString(for: status))")
            permissionCheckInProgress = false
            showingLocationAlert = true
        }
    }
    
    private func requestLocationPermissionAndStart() {
        print("🔐 [RouteDetail] 開始請求位置權限...")
        
        locationService.requestLocationPermission { success in
            DispatchQueue.main.async {
                permissionCheckInProgress = false
                
                if success {
                    print("✅ [RouteDetail] 權限獲取成功")
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
    
    private func startMonitoringDirectly() {
        permissionCheckInProgress = false
        
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
    
    private func checkPermissionStatusAndRetry() {
        print("🔄 [RouteDetail] 重新檢查權限狀態")
        
        let now = Date()
        if let lastCheck = lastPermissionCheck,
           now.timeIntervalSince(lastCheck) < 2.0 {
            print("⚠️ [RouteDetail] 權限檢查過於頻繁，跳過")
            return
        }
        lastPermissionCheck = now
        
        locationService.updateAuthorizationStatusSafely()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let (canUse, reason) = self.locationService.checkLocationServiceStatus()
            
            if canUse {
                print("✅ [RouteDetail] 重新檢查成功，開始監控")
                self.startMonitoringDirectly()
            } else {
                print("⚠️ [RouteDetail] 重新檢查後仍無權限: \(reason)")
            }
        }
    }
    
    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - 新的方向選擇按鈕元件

struct DirectionButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .blue)
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? .blue : .blue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? .clear : .blue.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 新的可互動站點行元件

struct StopRowView: View {
    let stop: BusStop.Stop
    let index: Int
    let arrival: BusArrival?
    let distance: Double
    let isNearest: Bool
    let isDestination: Bool
    let isMonitoring: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 站點序號
                ZStack {
                    Circle()
                        .fill(circleColor)
                        .frame(width: 32, height: 32)
                    
                    if isDestination {
                        Image(systemName: "flag.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                    } else {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                
                // 站點信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(stop.StopName.Zh_tw)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if isNearest {
                            Image(systemName: "location.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        
                        if isDestination {
                            Text("目的地")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.green))
                                .foregroundColor(.white)
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
                
                // 距離和狀態
                VStack(alignment: .trailing, spacing: 4) {
                    if distance != Double.infinity {
                        Text(formatDistance(distance))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(distanceColor)
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
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // 計算屬性保持不變，但移除邊框效果
    private var circleColor: Color {
        if isDestination { return .green }
        else if isNearest { return .orange }
        else { return .blue }
    }
    
    private var backgroundColor: Color {
        if isDestination { return .green.opacity(0.1) }
        else if isNearest { return .orange.opacity(0.1) }
        else { return .clear }
    }
    
    private var borderColor: Color {
        if isDestination {
            return .green.opacity(0.3)
        } else if isNearest {
            return .orange.opacity(0.3)
        } else {
            return .clear
        }
    }
    
    private var borderWidth: CGFloat {
        (isDestination || isNearest) ? 1 : 0
    }
    
    private var distanceColor: Color {
        if distance < 100 {
            return .red
        } else if distance < 300 {
            return .orange
        } else {
            return .secondary
        }
    }
    
    private func formatDistance(_ distance: Double) -> String {
        if distance < 1000 {
            return "\(Int(distance)) m"
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
}

// MARK: - 收藏按鈕元件（保持不變）

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
