//
//  SettingsView.swift
//  BusNotify
//
//  Created by Heidie Lee on 2025/5/15.
//

import SwiftUI
import UserNotifications

struct SettingsView: View {
    // 設定項目
    @AppStorage("notifyWithSound") private var notifyWithSound = true
    @AppStorage("notifyWithVibration") private var notifyWithVibration = true
    @AppStorage("notifyDistance") private var notifyDistance = 200.0
    @AppStorage("showEstimatedTime") private var showEstimatedTime = true
    @AppStorage("backgroundMonitoring") private var backgroundMonitoring = true
    @AppStorage("autoStopMonitoring") private var autoStopMonitoring = true
    @AppStorage("voiceAnnouncement") private var voiceAnnouncement = true
    
    // 狀態管理
    @State private var notificationPermissionStatus = "未知"
    @State private var locationPermissionStatus = "未知"
    @State private var showingResetAlert = false
    @State private var showingAboutSheet = false
    @StateObject private var tdxService = TDXService.shared
    
    var body: some View {
        NavigationView {
            List {
                // 通知設定
                notificationSection
                
                // 位置與監控設定
                locationSection
                
                // 顯示設定
                displaySection
                
                // 權限管理
                permissionsSection
                
                // 數據與隱私
                dataSection
                
                // 關於應用程式
                aboutSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                checkPermissions()
            }
            .sheet(isPresented: $showingAboutSheet) {
                AboutView()
            }
            .alert("重置設定", isPresented: $showingResetAlert) {
                Button("重置", role: .destructive) {
                    resetAllSettings()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("這將會重置所有設定為預設值，且無法復原。")
            }
        }
    }
    
    // 通知設定區塊
    private var notificationSection: some View {
        Section {
            // 聲音通知
            HStack {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("聲音通知")
                        .font(.subheadline)
                    Text("接近站點時播放提示音")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $notifyWithSound)
                    .labelsHidden()
            }
            
            // 震動通知
            HStack {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .foregroundColor(.orange)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("震動通知")
                        .font(.subheadline)
                    Text("配合聲音通知震動提醒")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $notifyWithVibration)
                    .labelsHidden()
            }
            
            // 語音播報
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(.purple)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("語音播報")
                        .font(.subheadline)
                    Text("語音播報站點名稱和到站資訊")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $voiceAnnouncement)
                    .labelsHidden()
            }
            
            // 通知距離設定
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "location.circle")
                        .foregroundColor(.green)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("通知距離")
                            .font(.subheadline)
                        Text("距離站點多遠時開始通知")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("\(Int(notifyDistance)) 公尺")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                
                Slider(value: $notifyDistance, in: 50...500, step: 50) {
                    Text("通知距離")
                } minimumValueLabel: {
                    Text("50m")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } maximumValueLabel: {
                    Text("500m")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .accentColor(.green)
            }
            
        } header: {
            Label("通知設定", systemImage: "bell.fill")
        } footer: {
            Text("這些設定會影響您接近公車站點時的通知行為")
        }
    }
    
    // 位置與監控設定區塊
    private var locationSection: some View {
        Section {
            // 背景監控
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("背景監控")
                        .font(.subheadline)
                    Text("允許在背景持續監控位置")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $backgroundMonitoring)
                    .labelsHidden()
            }
            
            // 自動停止監控
            HStack {
                Image(systemName: "stop.circle")
                    .foregroundColor(.red)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("自動停止監控")
                        .font(.subheadline)
                    Text("到達目的地後自動停止監控")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $autoStopMonitoring)
                    .labelsHidden()
            }
            
        } header: {
            Label("位置與監控", systemImage: "location.fill")
        } footer: {
            if backgroundMonitoring {
                Text("開啟背景監控可能會增加電池耗電量，但能提供更準確的位置提醒")
            } else {
                Text("關閉背景監控時，應用程式在背景可能無法正常工作")
            }
        }
    }
    
    // 顯示設定區塊
    private var displaySection: some View {
        Section {
            // 顯示預估到站時間
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.orange)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("顯示預估到站時間")
                        .font(.subheadline)
                    Text("在站點列表中顯示公車到站時間")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $showEstimatedTime)
                    .labelsHidden()
            }
            
        } header: {
            Label("顯示設定", systemImage: "eye.fill")
        }
    }
    
    // 權限管理區塊
    private var permissionsSection: some View {
        Section {
            // 位置權限狀態
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(locationPermissionStatus == "已授權" ? .green : .red)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("位置權限")
                        .font(.subheadline)
                    Text(locationPermissionStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("設定") {
                    openAppSettings()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // 通知權限狀態
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundColor(notificationPermissionStatus == "已授權" ? .green : .red)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("通知權限")
                        .font(.subheadline)
                    Text(notificationPermissionStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("設定") {
                    openAppSettings()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
        } header: {
            Label("權限管理", systemImage: "lock.shield.fill")
        } footer: {
            Text("應用程式需要位置和通知權限才能正常運作")
        }
    }
    
    // 數據與隱私區塊
    private var dataSection: some View {
        Section {
            // API 連線狀態
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(tdxService.errorMessage == nil ? .green : .red)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("TDX API 狀態")
                        .font(.subheadline)
                    Text(tdxService.errorMessage ?? "連線正常")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("測試") {
                    testAPIConnection()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // 清除收藏
            HStack {
                Image(systemName: "heart.slash")
                    .foregroundColor(.orange)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("清除收藏路線")
                        .font(.subheadline)
                    Text("移除所有收藏的路線")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("清除") {
                    clearFavorites()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // 重置設定
            HStack {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.red)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("重置所有設定")
                        .font(.subheadline)
                    Text("恢復為預設設定")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("重置") {
                    showingResetAlert = true
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
        } header: {
            Label("數據與隱私", systemImage: "shield.fill")
        }
    }
    
    // 關於應用程式區塊
    private var aboutSection: some View {
        Section {
            // 應用程式版本
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                Text("版本")
                    .font(.subheadline)
                
                Spacer()
                
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // 關於頁面
            Button(action: {
                showingAboutSheet = true
            }) {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(.green)
                        .frame(width: 24)
                    
                    Text("關於 BusNotify")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // TDX API
            Button(action: {
                if let url = URL(string: "https://tdx.transportdata.tw/") {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack {
                    Image(systemName: "link.circle.fill")
                        .foregroundColor(.purple)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TDX 運輸資料流通服務")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text("資料來源")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
        } header: {
            Label("關於", systemImage: "info.circle.fill")
        }
    }
    
    // 檢查權限狀態
    private func checkPermissions() {
        // 檢查位置權限
        let locationStatus = LocationService.shared.authorizationStatus
        switch locationStatus {
        case .authorizedAlways:
            locationPermissionStatus = "已授權（總是）"
        case .authorizedWhenInUse:
            locationPermissionStatus = "已授權（使用時）"
        case .denied:
            locationPermissionStatus = "已拒絕"
        case .restricted:
            locationPermissionStatus = "受限制"
        case .notDetermined:
            locationPermissionStatus = "未決定"
        @unknown default:
            locationPermissionStatus = "未知"
        }
        
        // 檢查通知權限
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized:
                    notificationPermissionStatus = "已授權"
                case .denied:
                    notificationPermissionStatus = "已拒絕"
                case .notDetermined:
                    notificationPermissionStatus = "未決定"
                case .provisional:
                    notificationPermissionStatus = "臨時授權"
                case .ephemeral:
                    notificationPermissionStatus = "短暫授權"
                @unknown default:
                    notificationPermissionStatus = "未知"
                }
            }
        }
    }
    
    // 開啟應用程式設定
    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    // 測試 API 連線
    private func testAPIConnection() {
        tdxService.testConnection { success in
            DispatchQueue.main.async {
                if success {
                    // 顯示成功提示
                } else {
                    // 顯示錯誤提示
                }
            }
        }
    }
    
    // 清除收藏
    private func clearFavorites() {
        UserDefaults.standard.removeObject(forKey: "favoriteRoutes")
    }
    
    // 重置所有設定
    private func resetAllSettings() {
        notifyWithSound = true
        notifyWithVibration = true
        notifyDistance = 200.0
        showEstimatedTime = true
        backgroundMonitoring = true
        autoStopMonitoring = true
        voiceAnnouncement = true
        
        // 清除收藏
        clearFavorites()
    }
}

// 關於頁面
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // 應用程式圖標和名稱
                    VStack(spacing: 16) {
                        Image(systemName: "bus.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                            .background(
                                Circle()
                                    .fill(.blue.opacity(0.1))
                                    .frame(width: 120, height: 120)
                            )
                        
                        VStack(spacing: 4) {
                            Text("BusNotify")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            Text("公車站點通知小幫手")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 20)
                    
                    // 功能介紹
                    VStack(alignment: .leading, spacing: 16) {
                        Text("主要功能")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        FeatureRow(
                            icon: "location.fill",
                            title: "智慧位置監控",
                            description: "即時監控您的位置，在接近目標站點時主動通知"
                        )
                        
                        FeatureRow(
                            icon: "bell.fill",
                            title: "多種通知方式",
                            description: "支援聲音、震動、語音播報等多種提醒方式"
                        )
                        
                        FeatureRow(
                            icon: "heart.fill",
                            title: "收藏常用路線",
                            description: "收藏經常搭乘的路線，快速開始監控"
                        )
                        
                        FeatureRow(
                            icon: "clock.fill",
                            title: "即時到站資訊",
                            description: "整合 TDX 資料，提供準確的公車到站時間"
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    // 技術信息
                    VStack(alignment: .leading, spacing: 12) {
                        Text("技術資訊")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        InfoRow(title: "資料來源", value: "TDX 運輸資料流通服務")
                        InfoRow(title: "開發框架", value: "SwiftUI + UIKit")
                        InfoRow(title: "定位服務", value: "Core Location")
                        InfoRow(title: "版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    }
                    .padding(.horizontal, 20)
                    
                    // 免責聲明
                    VStack(alignment: .leading, spacing: 8) {
                        Text("免責聲明")
                            .font(.footnote)
                            .fontWeight(.semibold)
                        
                        Text("• 本應用程式的公車資訊來源為 TDX 運輸資料流通服務\n• 實際到站時間可能因交通狀況而有所差異\n• 請以現場實際狀況為準")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("關於")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// 功能介紹行
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// 信息行
struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}
