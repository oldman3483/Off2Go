//
//  ContentView.swift
//  Off2Go
//
//  Modified by Heidie Lee on 2025/5/15.
//

import SwiftUI
import UserNotifications
import Combine

struct ContentView: View {
    @State private var selectedTab = 0
    @EnvironmentObject var locationService: LocationService
    @StateObject private var monitoringService = StationMonitoringService()
    @State private var showingPermissionAlert = false
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ZStack {
            // 主要標籤視圖
            TabView(selection: $selectedTab) {
                RouteSelectionView()
                    .tabItem {
                        VStack {
                            Image(systemName: selectedTab == 0 ? "bus.fill" : "bus")
                                .environment(\.symbolVariants, selectedTab == 0 ? .fill : .none)
                            Text("路線")
                        }
                    }
                    .tag(0)
                
                FavoritesView()
                    .tabItem {
                        VStack {
                            Image(systemName: selectedTab == 1 ? "star.fill" : "star")
                                .environment(\.symbolVariants, selectedTab == 1 ? .fill : .none)
                            Text("收藏")
                        }
                    }
                    .tag(1)
                    .badge(getFavoritesCount())
                
                SettingsView()
                    .tabItem {
                        VStack {
                            Image(systemName: selectedTab == 2 ? "gear.circle.fill" : "gear.circle")
                                .environment(\.symbolVariants, selectedTab == 2 ? .fill : .none)
                            Text("設定")
                        }
                    }
                    .tag(2)
            }
            .accentColor(.blue)
            
            // 監控狀態懸浮窗
            if monitoringService.isMonitoring {
                VStack {
                    Spacer()
                    MonitoringFloatingView(monitoringService: monitoringService)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 100) // 避免與標籤欄重疊
                }
                .allowsHitTesting(false) // 允許點擊穿透
            }
        }
        .onAppear {
            setupInitialState()
            setupPermissionMonitoring()
        }
        .alert("權限設定", isPresented: $showingPermissionAlert) {
            Button("前往設定") {
                openAppSettings()
            }
            Button("稍後設定", role: .cancel) {
                // 用戶選擇稍後設定，記錄這個選擇
                print("ℹ️ [ContentView] 用戶選擇稍後設定權限")
            }
        } message: {
            let (canUse, reason) = locationService.checkLocationServiceStatus()
            
            if !canUse {
                Text("Off2Go 需要位置權限才能提供到站提醒功能。\n\n\(reason)")
            } else {
                Text("建議開啟通知權限以接收到站提醒。")
            }
        }
    }
    
    // 設置初始狀態
    private func setupInitialState() {
        // 設置外觀
        setupAppearance()
        
        // 延遲檢查權限，確保視圖已完全載入，並且不會太頻繁調用
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.checkPermissions()
        }
    }
    
    // 設置權限監聽
    private func setupPermissionMonitoring() {
        // 監聽位置權限變化
        locationService.$authorizationStatus
            .sink { status in
                print("🔄 [ContentView] 位置權限狀態變化: \(locationService.authorizationStatusString)")
                
                // 如果權限從拒絕變成允許，自動隱藏警告
                if status == .authorizedWhenInUse || status == .authorizedAlways {
                    showingPermissionAlert = false
                }
            }
            .store(in: &cancellables)
    }
    
    // 檢查權限 - 修復版本
    private func checkPermissions() {
        print("🔍 [ContentView] 開始檢查應用權限...")
        
        // 不要在這裡調用任何位置管理器方法，避免主線程警告
        let currentStatus = locationService.getCurrentAuthorizationStatus()
        let (canUse, reason) = locationService.checkLocationServiceStatus()
        
        print("📍 [ContentView] 位置服務狀態: \(canUse ? "正常" : "異常") - \(reason)")
        print("📍 [ContentView] 實際權限狀態: \(locationService.statusString(for: currentStatus))")
        
        // 檢查通知權限
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let notificationStatus = settings.authorizationStatus
                print("🔔 [ContentView] 通知權限狀態: \(self.notificationStatusString(status: notificationStatus))")
                
                // 如果通知權限未決定，請求權限
                if notificationStatus == .notDetermined {
                    self.requestNotificationPermission()
                }
                
                // 只有在位置權限明確被拒絕時才顯示提示
                if currentStatus == .denied {
                    print("⚠️ [ContentView] 位置權限被拒絕，顯示提示")
                    self.showingPermissionAlert = true
                }
            }
        }
    }
    
    // 請求通知權限
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ [ContentView] 通知權限請求失敗: \(error.localizedDescription)")
                } else {
                    print("\(granted ? "✅" : "❌") [ContentView] 通知權限請求\(granted ? "成功" : "被拒絕")")
                }
            }
        }
    }
    
    // 通知狀態字串描述
    private func notificationStatusString(status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "未決定"
        case .denied: return "已拒絕"
        case .authorized: return "已授權"
        case .provisional: return "臨時授權"
        case .ephemeral: return "短暫授權"
        @unknown default: return "未知狀態"
        }
    }
    
    // 設置外觀
    private func setupAppearance() {
        // 設置標籤欄外觀
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBackground
        
        // 設置選中狀態的顏色
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor.systemBlue
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.systemBlue]
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        
        // 設置導航欄外觀
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor.systemBackground
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
        
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
    }
    
    // 獲取收藏數量
    private func getFavoritesCount() -> Int {
        if let data = UserDefaults.standard.data(forKey: "favoriteRoutes"),
           let routes = try? JSONDecoder().decode([BusRoute].self, from: data) {
            return routes.count
        }
        return 0
    }
    
    // 開啟應用程式設定
    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// 監控狀態懸浮視圖
struct MonitoringFloatingView: View {
    @ObservedObject var monitoringService: StationMonitoringService
    @State private var isExpanded = false
    
    var body: some View {
        HStack {
            Spacer()
            
            VStack(spacing: 0) {
                // 主要監控指示器
                Button(action: {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        // 監控狀態圖標
                        ZStack {
                            Circle()
                                .fill(.green)
                                .frame(width: 12, height: 12)
                            
                            Circle()
                                .fill(.green.opacity(0.3))
                                .frame(width: 20, height: 20)
                                .scaleEffect(isExpanded ? 1.5 : 1.0)
                                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isExpanded)
                        }
                        
                        if !isExpanded {
                            Text("監控中")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        
                        if isExpanded {
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.black.opacity(0.8))
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                // 擴展的監控資訊
                if isExpanded {
                    VStack(spacing: 8) {
                        if let route = monitoringService.selectedRoute {
                            // 路線資訊
                            HStack {
                                Text("路線:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Text(route.RouteName.Zh_tw)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                
                                Text(monitoringService.selectedDirection == 0 ? "去程" : "回程")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.blue.opacity(0.2)))
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        // 監控統計
                        let stats = monitoringService.getMonitoringStats()
                        HStack(spacing: 12) {
                            VStack(spacing: 2) {
                                Text("\(Int(stats.duration / 60))")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                Text("分鐘")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(spacing: 2) {
                                Text("\(stats.notifiedCount)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.orange)
                                Text("已通知")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(spacing: 2) {
                                Text("\(stats.totalStops)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                Text("總站點")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 最近站點
                        if let nearestIndex = monitoringService.nearestStopIndex,
                           nearestIndex < monitoringService.stops.count {
                            let nearestStop = monitoringService.stops[nearestIndex]
                            let distance = monitoringService.distanceToStop(nearestStop)
                            
                            HStack {
                                Image(systemName: "location.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                
                                Text(nearestStop.StopName.Zh_tw)
                                    .font(.caption)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text("\(Int(distance))m")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(distance < 100 ? .red : .primary)
                            }
                        }
                        
                        // 快速操作按鈕
                        HStack(spacing: 8) {
                            // 停止監控按鈕
                            Button(action: {
                                monitoringService.stopMonitoring()
                                withAnimation {
                                    isExpanded = false
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "stop.fill")
                                        .font(.caption2)
                                    Text("停止")
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(.red.opacity(0.2)))
                                .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // 重置通知按鈕
                            Button(action: {
                                monitoringService.resetNotificationStatus()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption2)
                                    Text("重置")
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(.blue.opacity(0.2)))
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.8)).combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.8))
                    ))
                    .padding(.top, 4)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationService.shared)
}
