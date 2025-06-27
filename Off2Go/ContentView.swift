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
    @EnvironmentObject var audioService: AudioNotificationService
    
    @State private var showingPermissionAlert = false
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
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
        .onAppear {
            setupInitialState()
            setupPermissionMonitoring()
        }
        .alert("權限設定", isPresented: $showingPermissionAlert) {
            Button("前往設定") {
                openAppSettings()
            }
            Button("稍後設定", role: .cancel) { }
        } message: {
            let (canUse, reason) = locationService.checkLocationServiceStatus()
            
            if !canUse {
                Text("Off2Go 需要位置權限才能提供到站提醒功能。\n\n\(reason)")
            } else {
                Text("建議開啟通知權限以接收到站提醒。")
            }
        }
    }
    
    // MARK: - 初始設定
    
    private func setupInitialState() {
        setupAppearance()
        
        // 延遲檢查權限
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.checkPermissions()
        }
    }
    
    private func setupPermissionMonitoring() {
        locationService.$authorizationStatus
            .sink { status in
                print("🔄 [ContentView] 位置權限狀態變化: \(self.locationService.authorizationStatusString)")
                
                if status == .authorizedWhenInUse || status == .authorizedAlways {
                    showingPermissionAlert = false
                }
            }
            .store(in: &cancellables)
    }
    
    private func checkPermissions() {
        print("🔍 [ContentView] 檢查應用權限...")
        
        let currentStatus = locationService.getCurrentAuthorizationStatus()
        let (canUse, reason) = locationService.checkLocationServiceStatus()
        
        print("📍 [ContentView] 位置服務狀態: \(canUse ? "正常" : "異常") - \(reason)")
        
        // 檢查通知權限
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let notificationStatus = settings.authorizationStatus
                print("🔔 [ContentView] 通知權限狀態: \(self.notificationStatusString(status: notificationStatus))")
                
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
    
    private func setupAppearance() {
        // 設置標籤欄外觀
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBackground
        
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
    
    private func getFavoritesCount() -> Int {
        if let data = UserDefaults.standard.data(forKey: "favoriteRoutes"),
           let routes = try? JSONDecoder().decode([BusRoute].self, from: data) {
            return routes.count
        }
        return 0
    }
    
    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
