//
//  AudioSettingsView.swift - 完整優化版
//  Off2Go
//
//  簡化介面，修復測試功能
//

import SwiftUI
import AVFoundation

struct AudioSettingsView: View {
    @StateObject private var audioService = AudioNotificationService.shared
    @StateObject private var waitingService = WaitingBusService.shared
    @State private var showingLanguageSheet = false
    @State private var showingTestAlert = false
    @State private var testMessage = ""
    
    // 語音語言選項
    private let availableLanguages = [
        ("zh-TW", "繁體中文"),
        ("zh-CN", "簡體中文"),
        ("en-US", "English (US)"),
        ("ja-JP", "日本語")
    ]
    
    var body: some View {
        NavigationView {
            List {
                // 狀態總覽
                statusOverviewSection
                
                // 基本設定
                basicSettingsSection
                
                // 語音設定
                voiceSettingsSection
                
                // 目的地設定
                destinationSection
                
                // 等車提醒管理
                waitingAlertsSection
                
                // 測試功能
                testingSection
                
                // 使用說明
                instructionsSection
            }
            .navigationTitle("音頻設定")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingLanguageSheet) {
                LanguageSelectionSheet(
                    selectedLanguage: audioService.voiceLanguage,
                    availableLanguages: availableLanguages
                ) { language in
                    audioService.setVoiceLanguage(language)
                }
            }
            .alert("測試結果", isPresented: $showingTestAlert) {
                Button("確定", role: .cancel) { }
            } message: {
                Text(testMessage)
            }
        }
    }
    
    // MARK: - 狀態總覽
    
    private var statusOverviewSection: some View {
        Section {
            VStack(spacing: 12) {
                // 音頻狀態
                HStack {
                    Image(systemName: audioService.isAudioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .foregroundColor(audioService.isAudioEnabled ? .green : .red)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("語音播報")
                            .font(.headline)
                        Text(audioService.isAudioEnabled ? "已開啟" : "已關閉")
                            .font(.subheadline)
                            .foregroundColor(audioService.isAudioEnabled ? .green : .red)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { audioService.isAudioEnabled },
                        set: { _ in audioService.toggleAudioNotifications() }
                    ))
                    .labelsHidden()
                }
                
                // 耳機狀態
                HStack {
                    Image(systemName: audioService.isHeadphonesConnected ? "headphones" : "speaker.wave.2")
                        .foregroundColor(audioService.isHeadphonesConnected ? .blue : .orange)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("音頻輸出")
                            .font(.subheadline)
                        Text(audioService.isHeadphonesConnected ? "耳機" : "揚聲器")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if audioService.isHeadphonesConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Text("建議使用耳機")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                // 目的地狀態
                if let destination = audioService.currentDestination {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("目的地")
                                .font(.subheadline)
                            Text(destination)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        
                        Spacer()
                        
                        Button("清除") {
                            audioService.clearDestination()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
            
        } header: {
            Label("狀態總覽", systemImage: "info.circle")
        }
    }
    
    // MARK: - 基本設定
    
    private var basicSettingsSection: some View {
        Section {
            // 語音速度
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "speedometer")
                        .foregroundColor(.orange)
                        .frame(width: 24)
                    
                    Text("語音速度")
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Text(String(format: "%.1fx", audioService.speechRate * 2))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                
                Slider(
                    value: Binding(
                        get: { audioService.speechRate },
                        set: { audioService.setSpeechRate($0) }
                    ),
                    in: 0.2...1.0,
                    step: 0.1
                ) {
                    Text("語音速度")
                } minimumValueLabel: {
                    Text("慢")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } maximumValueLabel: {
                    Text("快")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .accentColor(.orange)
            }
            
            // 語音音量
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "speaker.wave.3")
                        .foregroundColor(.red)
                        .frame(width: 24)
                    
                    Text("語音音量")
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Text("\(Int(audioService.speechVolume * 100))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                
                Slider(
                    value: Binding(
                        get: { audioService.speechVolume },
                        set: { audioService.setSpeechVolume($0) }
                    ),
                    in: 0.1...1.0,
                    step: 0.1
                ) {
                    Text("語音音量")
                } minimumValueLabel: {
                    Image(systemName: "speaker")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .accentColor(.red)
            }
            
        } header: {
            Label("基本設定", systemImage: "gear")
        }
    }
    
    // MARK: - 語音設定
    
    private var voiceSettingsSection: some View {
        Section {
            Button(action: {
                showingLanguageSheet = true
            }) {
                HStack {
                    Image(systemName: "globe")
                        .foregroundColor(.purple)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("語音語言")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        if let currentLanguage = availableLanguages.first(where: { $0.0 == audioService.voiceLanguage }) {
                            Text(currentLanguage.1)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
        } header: {
            Label("語音設定", systemImage: "mic.fill")
        }
    }
    
    // MARK: - 目的地設定
    
    private var destinationSection: some View {
        Section {
            if let destination = audioService.currentDestination {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.green)
                        Text("目前目的地")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    
                    Text(destination)
                        .font(.subheadline)
                        .foregroundColor(.green)
                        .padding(.leading, 24)
                    
                    if audioService.isAudioEnabled {
                        HStack {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text("將在接近時語音提醒")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(.leading, 24)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "location")
                        .foregroundColor(.gray)
                    Text("尚未設定目的地")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
        } header: {
            Label("目的地", systemImage: "flag.fill")
        } footer: {
            Text("在路線詳情頁面選擇目標站點後，將自動設定語音提醒")
        }
    }
    
    // MARK: - 等車提醒管理
    
    private var waitingAlertsSection: some View {
        Section {
            if waitingService.activeAlerts.isEmpty {
                HStack {
                    Image(systemName: "bell")
                        .foregroundColor(.gray)
                    Text("無等車提醒")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ForEach(waitingService.activeAlerts) { alert in
                    HStack {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(alert.routeName) - \(alert.stopName)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("提前 \(alert.alertMinutes) 分鐘")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("取消") {
                            waitingService.removeWaitingAlert(alert)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                
                if waitingService.activeAlerts.count > 1 {
                    Button("清除全部") {
                        waitingService.clearAllAlerts()
                    }
                    .foregroundColor(.red)
                    .font(.subheadline)
                }
            }
            
        } header: {
            Label("等車提醒 (\(waitingService.activeAlerts.count))", systemImage: "bell.circle")
        }
    }
    
    // MARK: - 測試功能
    
    private var testingSection: some View {
        Section {
            // 測試一般語音
            Button(action: testGeneralVoice) {
                HStack {
                    Image(systemName: "play.circle")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("測試一般語音")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text("播放一般站點資訊")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // 測試等車提醒
            Button(action: testWaitingAlert) {
                HStack {
                    Image(systemName: "bell")
                        .foregroundColor(.orange)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("測試等車提醒")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text("播放緊急提醒語音")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // 測試到站提醒
            Button(action: testArrivalAlert) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("測試到站提醒")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text("播放最高優先級語音")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
        } header: {
            Label("測試功能", systemImage: "waveform")
        } footer: {
            Text("建議戴上耳機後再測試語音功能。等車提醒和到站提醒具有最高優先級，可以在背景播放。")
        }
    }
    
    // MARK: - 使用說明
    
    private var instructionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                InstructionRow(
                    icon: "1.circle.fill",
                    title: "設定目的地",
                    description: "在路線詳情頁面選擇目標站點，系統會自動開始語音提醒"
                )
                
                InstructionRow(
                    icon: "2.circle.fill",
                    title: "等車提醒",
                    description: "點擊站點旁的🔔圖示設定等車提醒，公車接近時會自動通知"
                )
                
                InstructionRow(
                    icon: "3.circle.fill",
                    title: "背景播放",
                    description: "App進入背景後仍可語音播報，建議連接耳機以獲得最佳體驗"
                )
                
                InstructionRow(
                    icon: "4.circle.fill",
                    title: "優先級系統",
                    description: "等車提醒 > 到站提醒 > 一般語音，緊急情況會優先播報"
                )
            }
            
        } header: {
            Label("使用說明", systemImage: "questionmark.circle")
        }
    }
    
    // MARK: - 測試方法
    
    private func testGeneralVoice() {
        let message = "這是一般語音測試，即將到達台北車站，預計1分鐘到站"
        audioService.announceStationInfo(stopName: "台北車站", arrivalTime: "預計1分鐘到站")
        
        testMessage = "一般語音測試已播放\n如果沒聽到聲音，請檢查音量設定"
        showingTestAlert = true
    }
    
    private func testWaitingAlert() {
        let message = "注意！701公車還有2分鐘到達台北車站，請準備前往站牌"
        audioService.announceWaitingBusAlert(message)
        
        testMessage = "等車提醒測試已播放\n這是最高優先級語音，可在背景播放"
        showingTestAlert = true
    }
    
    private func testArrivalAlert() {
        let message = "緊急提醒！您已到達目的地台北車站，請準備下車"
        audioService.announceArrivalAlert(message)
        
        testMessage = "到站提醒測試已播放\n這是高優先級語音，會中斷其他播報"
        showingTestAlert = true
    }
    
}

// 新增音頻診斷方法
func diagnoseAudioSession() {
    let audioSession = AVAudioSession.sharedInstance()
    
    print("🔍 [Audio] === 音頻會話診斷 ===")
    print("   當前類別: \(audioSession.category)")
    print("   當前模式: \(audioSession.mode)")
    print("   是否活躍: \(audioSession.isOtherAudioPlaying)")
    print("   可用類別: \(audioSession.availableCategories)")
    print("   可用模式: \(audioSession.availableModes)")
    print("   當前路由: \(audioSession.currentRoute.outputs.map { $0.portType })")
    
    #if targetEnvironment(simulator)
    print("⚠️ [Audio] 運行在模擬器上，某些音頻功能可能受限")
    #endif
}

// MARK: - 支援組件

struct InstructionRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.title3)
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

struct LanguageSelectionSheet: View {
    let selectedLanguage: String
    let availableLanguages: [(String, String)]
    let onLanguageSelected: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(availableLanguages, id: \.0) { language in
                    Button(action: {
                        onLanguageSelected(language.0)
                        dismiss()
                    }) {
                        HStack {
                            Text(language.1)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if selectedLanguage == language.0 {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .navigationTitle("選擇語言")
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
