//
//  AudioSettingsView.swift
//  Off2Go
//
//  Audio settings for headphone notifications
//

import SwiftUI
import AVFoundation

struct AudioSettingsView: View {
    @StateObject private var audioService = AudioNotificationService.shared
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
                // 耳機狀態
                headphoneStatusSection
                
                // 基本設定
                basicSettingsSection
                
                // 語音設定
                voiceSettingsSection
                
                // 目的地設定
                destinationSettingsSection
                
                // 測試功能
                testSection
                
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
            .alert("測試完成", isPresented: $showingTestAlert) {
                Button("確定", role: .cancel) { }
            } message: {
                Text(testMessage)
            }
        }
    }
    
    // MARK: - 耳機狀態區塊
    
    private var headphoneStatusSection: some View {
        Section {
            HStack {
                Image(systemName: audioService.isHeadphonesConnected ? "headphones" : "speaker.wave.2.slash")
                    .foregroundColor(audioService.isHeadphonesConnected ? .green : .orange)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("耳機狀態")
                        .font(.headline)
                    
                    Text(audioService.isHeadphonesConnected ? "已連接" : "未連接")
                        .font(.subheadline)
                        .foregroundColor(audioService.isHeadphonesConnected ? .green : .orange)
                }
                
                Spacer()
                
                if audioService.isHeadphonesConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
            }
            .padding(.vertical, 4)
            
            if !audioService.isHeadphonesConnected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("建議使用耳機")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Text("連接有線或藍牙耳機可獲得更好的音頻體驗，且不會打擾他人")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.blue.opacity(0.1))
                )
            }
            
        } header: {
            Label("設備狀態", systemImage: "headphones")
        }
    }
    
    // MARK: - 基本設定區塊
    
    private var basicSettingsSection: some View {
        Section {
            // 音頻提醒開關
            HStack {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("音頻提醒")
                        .font(.subheadline)
                    Text("開啟語音播報和提示音")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { audioService.isAudioEnabled },
                    set: { _ in audioService.toggleAudioNotifications() }
                ))
                .labelsHidden()
            }
            
            // 提醒距離設定
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "location.circle")
                        .foregroundColor(.green)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("提醒距離")
                            .font(.subheadline)
                        Text("提前幾站開始提醒")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("\(audioService.notificationDistance) 站")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                
                HStack(spacing: 16) {
                    Button(action: {
                        audioService.decreaseNotificationDistance()
                    }) {
                        Image(systemName: "minus.circle")
                            .foregroundColor(audioService.notificationDistance > 1 ? .blue : .gray)
                    }
                    .disabled(audioService.notificationDistance <= 1)
                    
                    HStack {
                        ForEach(1...5, id: \.self) { number in
                            Circle()
                                .fill(number <= audioService.notificationDistance ? .blue : .gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    
                    Button(action: {
                        audioService.increaseNotificationDistance()
                    }) {
                        Image(systemName: "plus.circle")
                            .foregroundColor(audioService.notificationDistance < 5 ? .blue : .gray)
                    }
                    .disabled(audioService.notificationDistance >= 5)
                    
                    Spacer()
                }
            }
            
        } header: {
            Label("基本設定", systemImage: "gear")
        } footer: {
            Text("提醒距離決定在距離目的地前幾站開始語音提醒")
        }
    }
    
    // MARK: - 語音設定區塊
    
    private var voiceSettingsSection: some View {
        Section {
            // 語音語言
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
            
            // 語音速度
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "speedometer")
                        .foregroundColor(.orange)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("語音速度")
                            .font(.subheadline)
                        Text("調整播報速度")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
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
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("語音音量")
                            .font(.subheadline)
                        Text("調整播報音量")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
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
            Label("語音設定", systemImage: "mic.fill")
        }
    }
    
    // MARK: - 目的地設定區塊
    
    private var destinationSettingsSection: some View {
        Section {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.green)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("目前目的地")
                        .font(.subheadline)
                    
                    if let destination = audioService.currentDestination {
                        Text(destination)
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("未設定")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if audioService.currentDestination != nil {
                    Button("清除") {
                        audioService.clearDestination()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
            
        } header: {
            Label("目的地", systemImage: "flag.fill")
        } footer: {
            Text("在路線詳情頁面選擇目標站點後，將自動設定音頻提醒")
        }
    }
    
    // MARK: - 測試區塊
    
    private var testSection: some View {
        Section {
            // 測試語音播報
            Button(action: testVoiceAnnouncement) {
                HStack {
                    Image(systemName: "play.circle")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("測試語音播報")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text("播放測試音頻")
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
            Button(action: testArrivalNotification) {
                HStack {
                    Image(systemName: "bell")
                        .foregroundColor(.orange)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("測試到站提醒")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text("模擬即將到站通知")
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
        }
    }
    
    // MARK: - 使用說明區塊
    
    private var instructionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                InstructionRow(
                    icon: "1.circle.fill",
                    title: "選擇路線",
                    description: "在路線詳情頁面選擇您要搭乘的公車路線"
                )
                
                InstructionRow(
                    icon: "2.circle.fill",
                    title: "設定目的地",
                    description: "點選目標站點並啟用音頻提醒功能"
                )
                
                InstructionRow(
                    icon: "3.circle.fill",
                    title: "連接耳機",
                    description: "建議連接耳機以獲得最佳體驗"
                )
                
                InstructionRow(
                    icon: "4.circle.fill",
                    title: "開始監控",
                    description: "應用程式將在接近目的地前提醒您"
                )
            }
            
        } header: {
            Label("使用說明", systemImage: "questionmark.circle")
        }
    }
    
    // MARK: - 測試方法
    
    private func testVoiceAnnouncement() {
        let testMessage = "這是 Off2Go 音頻測試，語音播報功能正常"
        audioService.announceStationInfo(stopName: "測試站點", arrivalTime: testMessage)
        
        self.testMessage = "語音測試已播放"
        showingTestAlert = true
    }
    
    private func testArrivalNotification() {
        audioService.announceStationInfo(
            stopName: "台北車站",
            arrivalTime: "即將到站，請準備下車"
        )
        
        self.testMessage = "到站提醒測試已播放"
        showingTestAlert = true
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

#Preview {
    AudioSettingsView()
}
