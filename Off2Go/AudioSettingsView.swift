//
//  AudioSettingsView.swift - 完整優化版（移除測試功能）
//  Off2Go
//
//  新增智慧音頻設定，移除測試功能
//

import SwiftUI
import AVFoundation
import MediaPlayer

struct AudioSettingsView: View {
    @StateObject private var audioService = AudioNotificationService.shared
    @StateObject private var waitingService = WaitingBusService.shared
    @State private var showingLanguageSheet = false
    
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
                
                // 音頻混合設定
                audioMixingSection
                
                // 語音設定
                voiceSettingsSection
                
                // 目的地設定
                destinationSection
                
                // 等車提醒管理
                waitingAlertsSection
                
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
    
    // MARK: - 音頻混合設定
    
    private var audioMixingSection: some View {
        Section {
            // 智慧音量調整（保持原有）
            HStack {
                Image(systemName: "speaker.wave.2.circle")
                    .foregroundColor(.purple)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("智慧音量調整")
                        .font(.subheadline)
                    Text("自動偵測其他音頻並調整播報方式")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { audioService.smartVolumeEnabled },
                    set: { newValue in
                        if newValue != audioService.smartVolumeEnabled {
                            audioService.toggleSmartVolume()
                        }
                    }
                ))
                .labelsHidden()
            }
            
            // 影片模式處理
            HStack {
                Image(systemName: "play.rectangle")
                    .foregroundColor(.red)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("影片模式")
                        .font(.subheadline)
                    Text("觀看影片時使用疊加播報")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { audioService.videoModeEnabled },
                    set: { newValue in
                        if newValue != audioService.videoModeEnabled {
                            audioService.toggleVideoMode()
                        }
                    }
                ))
                .labelsHidden()
                .disabled(!audioService.smartVolumeEnabled)
            }
            .opacity(audioService.smartVolumeEnabled ? 1.0 : 0.6)
            
            // 當前音頻狀態顯示
            if audioService.smartVolumeEnabled {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("當前狀態")
                            .font(.subheadline)
                        Text(getAudioStatusText())
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.blue.opacity(0.1))
                )
            }
            
        } header: {
            Label("音頻混合設定", systemImage: "waveform.path")
        } footer: {
            if audioService.smartVolumeEnabled {
                Text("智慧音量調整會自動偵測其他音頻並選擇最佳播報方式。影片模式在偵測到影片播放時不會降低原音量。")
            } else {
                Text("關閉智慧音量調整後，將使用標準音頻設定，可能會與其他音頻產生衝突。")
            }
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
                    title: "智慧音頻",
                    description: "自動偵測影片或音樂播放，調整語音播報方式避免衝突"
                )
            }
            
        } header: {
            Label("使用說明", systemImage: "questionmark.circle")
        }
    }
    
    // MARK: - 輔助方法
    
    private func getAudioStatusText() -> String {
        let audioSession = AVAudioSession.sharedInstance()
        let isOtherAudioPlaying = audioSession.isOtherAudioPlaying
        
        if !isOtherAudioPlaying {
            return "無其他音頻播放"
        } else if audioService.videoModeEnabled && checkIfVideoContent() {
            return "偵測到影片音頻 - 將使用疊加模式"
        } else {
            return "偵測到音樂音頻 - 將使用智慧降音模式"
        }
    }
    
    private func checkIfVideoContent() -> Bool {
        let nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
        if let mediaType = nowPlayingInfo?[MPMediaItemPropertyMediaType] as? NSNumber {
            let type = MPMediaType(rawValue: mediaType.uintValue)
            return type.contains(.movie) || type.contains(.tvShow)
        }
        return false
    }
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
