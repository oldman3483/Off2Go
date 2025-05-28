//
//  AudioNotificationService.swift
//  Off2Go
//
//  Created by Heidie Lee on 2025/5/27.
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine

class AudioNotificationService: NSObject, ObservableObject {
    static let shared = AudioNotificationService()
    
    // 音頻設定
    @Published var isAudioEnabled: Bool = true
    @Published var isHeadphonesConnected: Bool = false
    @Published var currentDestination: String?
    @Published var targetStopName: String?
    @Published var notificationDistance: Int = 2
    
    // 音頻引擎
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()
    private var audioPlayer: AVAudioPlayer?
    
    // 語音設定
    private var _voiceLanguage: String = "zh-TW"
    private var _speechRate: Float = 0.5
    private var _speechVolume: Float = 1.0
    
    // 防重複播報機制
    private var lastAnnouncementTime: Date?
    private var lastAnnouncementContent: String?
    private let minimumAnnouncementInterval: TimeInterval = 8.0 // 增加間隔時間
    private var pendingSpeechQueue: [String] = []
    private var isSpeaking: Bool = false
    
    // 目的地設定狀態
    private var isSettingDestination: Bool = false
    private var lastDestinationSetTime: Date?
    
    // 監控狀態
    private var isMonitoring = false
    private var cancellables = Set<AnyCancellable>()
    
    // 目的地設定
    private var destinationRoute: String?
    private var destinationStop: String?
    private var hasNotifiedApproaching = false
    private var hasNotifiedArrival = false
    
    // 語音狀態追蹤
    private var speechQueue: DispatchQueue
    
    override init() {
        speechQueue = DispatchQueue(label: "com.off2go.speech", qos: .userInitiated)
        super.init()
        setupAudioSession()
        setupHeadphoneDetection()
        setupRemoteControl()
        setupSpeechSynthesizerDelegate()
        loadSettings()
    }
    
    // MARK: - 語音狀態管理
    

    func setupSpeechSynthesizerDelegate() {
        speechSynthesizer.delegate = self
    }
    
    // 檢查是否可以播報
    private func canAnnounce(_ content: String) -> Bool {
        let now = Date()
        
        // 檢查是否正在播報
        if isSpeaking || speechSynthesizer.isSpeaking {
            print("🔇 [Audio] 正在播報中，跳過新的播報: \(content)")
            return false
        }
        
        // 檢查是否為完全相同的內容
        if let lastContent = lastAnnouncementContent,
           lastContent == content {
            if let lastTime = lastAnnouncementTime,
               now.timeIntervalSince(lastTime) < minimumAnnouncementInterval {
                print("🔇 [Audio] 重複內容且時間間隔過短（\(now.timeIntervalSince(lastTime))s），跳過播報: \(content)")
                return false
            }
        }
        
        // 檢查時間間隔（任何播報之間至少間隔 3 秒）
        if let lastTime = lastAnnouncementTime,
           now.timeIntervalSince(lastTime) < 3.0 {
            print("🔇 [Audio] 播報間隔過短（\(now.timeIntervalSince(lastTime))s），跳過")
            return false
        }
        
        // 特殊檢查：目的地設定播報
        if content.contains("目的地已設定") {
            if let lastDestinationTime = lastDestinationSetTime,
               now.timeIntervalSince(lastDestinationTime) < 5.0 {
                print("🔇 [Audio] 目的地設定播報間隔過短，跳過")
                return false
            }
        }
        
        return true
    }
    
    // 更新播報記錄
    private func updateAnnouncementHistory(_ content: String) {
        let now = Date()
        lastAnnouncementTime = now
        lastAnnouncementContent = content
        isSpeaking = true
        
        // 如果是目的地設定播報，記錄時間
        if content.contains("目的地已設定") {
            lastDestinationSetTime = now
        }
    }
    
    // MARK: - 語音播報修復版本
    
    private func speakMessage(_ message: String, priority: SpeechPriority) {
        // 使用串行隊列確保播報順序
        speechQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 在主線程檢查播報條件
            DispatchQueue.main.sync {
                // 檢查基本條件
                guard self.isAudioEnabled && (self.isHeadphonesConnected || self.allowSpeakerOutput()) else {
                    print("🔇 [Audio] 播報條件不滿足")
                    return
                }
                
                // 檢查是否可以播報
                guard self.canAnnounce(message) else {
                    return
                }
                
                print("🎤 [Audio] 準備播報: \(message)")
                
                // 根據優先級處理
                switch priority {
                case .urgent:
                    // 緊急情況：立即停止當前播報
                    if self.speechSynthesizer.isSpeaking {
                        self.speechSynthesizer.stopSpeaking(at: .immediate)
                    }
                    self.performSpeech(message, priority: priority)
                    
                case .high:
                    // 高優先級：停止當前播報後執行
                    if self.speechSynthesizer.isSpeaking {
                        self.speechSynthesizer.stopSpeaking(at: .word)
                        // 延遲確保停止完成
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.performSpeech(message, priority: priority)
                        }
                    } else {
                        self.performSpeech(message, priority: priority)
                    }
                    
                case .normal:
                    // 普通優先級：等待或加入隊列
                    if self.speechSynthesizer.isSpeaking {
                        // 檢查隊列中是否已有相同內容
                        if !self.pendingSpeechQueue.contains(message) {
                            self.pendingSpeechQueue.append(message)
                            print("🎤 [Audio] 加入播報隊列: \(message)")
                        }
                    } else {
                        self.performSpeech(message, priority: priority)
                    }
                }
            }
        }
    }
    
    private func performSpeech(_ message: String, priority: SpeechPriority) {
        updateAnnouncementHistory(message)
        
        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: _voiceLanguage)
        
        // 根據優先級調整語音參數
        switch priority {
        case .urgent:
            utterance.rate = 0.4
            utterance.volume = 1.0
            utterance.preUtteranceDelay = 0.1
        case .high:
            utterance.rate = 0.45
            utterance.volume = 0.9
            utterance.preUtteranceDelay = 0.2
        case .normal:
            utterance.rate = _speechRate
            utterance.volume = _speechVolume
            utterance.preUtteranceDelay = 0.5
        }
        
        speechSynthesizer.speak(utterance)
        print("🎤 [Audio] 開始播報: \(message)")
    }
    
    // MARK: - 站點通知修復版本
    
    func checkStationProximity(currentStops: [BusStop.Stop], nearestStopIndex: Int?) {
        guard isMonitoring,
              isAudioEnabled,
              let targetStop = destinationStop,
              let nearestIndex = nearestStopIndex,
              nearestIndex < currentStops.count else {
            return
        }
        
        let currentStop = currentStops[nearestIndex]
        let remainingStops = calculateRemainingStops(
            currentStops: currentStops,
            currentIndex: nearestIndex,
            targetStopName: targetStop
        )
        
        // 防重複通知的關鍵檢查
        let currentStopID = currentStop.StopID
        let proximityKey = "proximity_\(currentStopID)_\(remainingStops)"
        
        if hasRecentlyNotified(key: proximityKey) {
            return
        }
        
        // 檢查是否需要提前通知
        if remainingStops == notificationDistance && !hasNotifiedApproaching {
            announceApproachingDestination(remainingStops: remainingStops)
            hasNotifiedApproaching = true
            recordNotification(key: proximityKey)
        }
        
        // 檢查是否到達目的地
        if currentStop.StopName.Zh_tw.contains(targetStop) && !hasNotifiedArrival {
            announceArrivalAtDestination()
            hasNotifiedArrival = true
            recordNotification(key: "arrival_\(currentStopID)")
        }
    }
    
    // 通知記錄管理
    private var notificationHistory: [String: Date] = [:]
    
    private func hasRecentlyNotified(key: String) -> Bool {
        if let lastTime = notificationHistory[key] {
            return Date().timeIntervalSince(lastTime) < 30.0
        }
        return false
    }
    
    private func recordNotification(key: String) {
        notificationHistory[key] = Date()
        
        // 清理過期記錄
        let cutoffTime = Date().addingTimeInterval(-300)
        notificationHistory = notificationHistory.filter { $0.value > cutoffTime }
    }
    
    // MARK: - 修復後的通知方法
    
    private func announceDestinationSet(routeName: String, stopName: String) {
        let message = "目的地已設定為\(stopName)，將在前\(notificationDistance)站提醒您"
        speakMessage(message, priority: .high)
    }
    
    private func announceDestinationCleared() {
        let message = "目的地已取消"
        speakMessage(message, priority: .normal)
    }
    
    private func announceApproachingDestination(remainingStops: Int) {
        guard let targetStop = destinationStop else { return }
        let message = "提醒您，再\(remainingStops)站就到\(targetStop)，請準備下車"
        
        speakMessage(message, priority: .high)
        playNotificationSound()
        updateNowPlayingInfo(with: "即將到站提醒")
    }
    
    private func announceArrivalAtDestination() {
        guard let targetStop = destinationStop else { return }
        let message = "\(targetStop)到了，請準備下車"
        
        speakMessage(message, priority: .urgent)
        playNotificationSound()
        updateNowPlayingInfo(with: "已到達目的地")
        
        // 延遲清除目的地
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.clearDestination()
        }
    }
    
    func announceStationInfo(stopName: String, arrivalTime: String? = nil) {
        let baseMessage = "即將到達\(stopName)"
        var message = baseMessage
        
        if let time = arrivalTime, !time.isEmpty, time != baseMessage {
            message += "，\(time)"
        }
        
        speakMessage(message, priority: .normal)
    }
    
    // MARK: - 目的地設定
    
    func setDestination(_ routeName: String, stopName: String) {
        // 防止重複設定
        if isSettingDestination {
            print("🎯 [Audio] 正在設定目的地中，跳過重複設定")
            return
        }
        
        // 檢查是否為相同目的地
        if destinationRoute == routeName && destinationStop == stopName {
            print("🎯 [Audio] 目的地未變更，跳過設定")
            return
        }
        
        isSettingDestination = true
        
        destinationRoute = routeName
        destinationStop = stopName
        targetStopName = stopName
        currentDestination = routeName.isEmpty ? stopName : "\(routeName) - \(stopName)"
        
        // 重置通知狀態
        hasNotifiedApproaching = false
        hasNotifiedArrival = false
        notificationHistory.removeAll()
        
        startMonitoring()
        
        // 延遲播報，避免重複
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.announceDestinationSet(routeName: routeName, stopName: stopName)
            self.isSettingDestination = false
        }
        
        print("🎯 [Audio] 設定目的地: \(routeName) - \(stopName)")
    }
    
    func clearDestination() {
        destinationRoute = nil
        destinationStop = nil
        targetStopName = nil
        currentDestination = nil
        hasNotifiedApproaching = false
        hasNotifiedArrival = false
        notificationHistory.removeAll()
        isSettingDestination = false
        
        stopMonitoring()
        announceDestinationCleared()
        
        print("🗑️ [Audio] 已清除目的地")
    }
    
    // MARK: - 其他方法保持不變
    
    private func setupAudioSession() {
        do {
            // 1. 先停用當前會話
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            
            // 2. 設定音頻類別
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .allowBluetooth, .allowBluetoothA2DP]
            )
            
            // 3. 延遲一點再啟用，避免 -50 錯誤
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                do {
                    try self.audioSession.setActive(true)
                    print("✅ [Audio] 音頻會話設定成功")
                } catch let error as NSError {
                    print("❌ [Audio] 延遲啟用音頻會話失敗: \(error.localizedDescription) (代碼: \(error.code))")
                    
                    // 最後嘗試最簡單的設定
                    self.fallbackAudioSetup()
                }
            }
            
        } catch let error as NSError {
            print("❌ [Audio] 音頻會話設定失敗: \(error.localizedDescription) (代碼: \(error.code))")
            fallbackAudioSetup()
        }
    }
    
    // 備用音頻設定
    private func fallbackAudioSetup() {
        do {
            // 使用最基本的設定
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            print("✅ [Audio] 使用備用音頻設定成功")
        } catch {
            print("❌ [Audio] 備用音頻設定也失敗: \(error.localizedDescription)")
            // 即使音頻設定失敗，也不影響其他功能
        }
    }
    
    private func setupHeadphoneDetection() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        checkHeadphoneConnection()
    }
    
    @objc private func audioRouteChanged(notification: Notification) {
        checkHeadphoneConnection()
    }
    
    private func checkHeadphoneConnection() {
        let currentRoute = audioSession.currentRoute
        var headphonesConnected = false
        
        for output in currentRoute.outputs {
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                headphonesConnected = true
                break
            default:
                break
            }
        }
        
        DispatchQueue.main.async {
            self.isHeadphonesConnected = headphonesConnected
        }
    }
    
    private func setupRemoteControl() {
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] event in
            self?.toggleAudioNotifications()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] event in
            self?.toggleAudioNotifications()
            return .success
        }
    }
    
    private func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        updateNowPlayingInfo()
        print("▶️ [Audio] 開始音頻監控")
    }
    
    private func stopMonitoring() {
        isMonitoring = false
        print("⏹️ [Audio] 停止音頻監控")
    }
    
    private func calculateRemainingStops(currentStops: [BusStop.Stop], currentIndex: Int, targetStopName: String) -> Int {
        for (index, stop) in currentStops.enumerated() {
            if index > currentIndex && stop.StopName.Zh_tw.contains(targetStopName) {
                return index - currentIndex
            }
        }
        return -1
    }
    
    private func playNotificationSound() {
        guard let soundURL = Bundle.main.url(forResource: "notification", withExtension: "mp3") else {
            playSystemSound()
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.volume = 0.7
            audioPlayer?.play()
        } catch {
            playSystemSound()
        }
    }
    
    private func playSystemSound() {
        AudioServicesPlaySystemSound(1007)
    }
    
    private func updateNowPlayingInfo(with status: String = "監控中") {
        var nowPlayingInfo = [String: Any]()
        
        if let destination = currentDestination {
            nowPlayingInfo[MPMediaItemPropertyTitle] = "Off2Go 到站提醒"
            nowPlayingInfo[MPMediaItemPropertyArtist] = destination
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = status
        } else {
            nowPlayingInfo[MPMediaItemPropertyTitle] = "Off2Go"
            nowPlayingInfo[MPMediaItemPropertyArtist] = "公車到站提醒"
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "待機中"
        }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isMonitoring ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func allowSpeakerOutput() -> Bool {
        return UserDefaults.standard.bool(forKey: "allowSpeakerOutput")
    }
    
    // MARK: - 設定控制
    
    func toggleAudioNotifications() {
        isAudioEnabled.toggle()
        saveSettings()
        
        let message = isAudioEnabled ? "語音提醒開啟" : "語音提醒關閉"
        speakMessage(message, priority: .normal)
        updateNowPlayingInfo()
    }
    
    func increaseNotificationDistance() {
        notificationDistance = min(notificationDistance + 1, 5)
        saveSettings()
        
        let message = "提醒距離已調整為前\(notificationDistance)站"
        speakMessage(message, priority: .normal)
    }
    
    func decreaseNotificationDistance() {
        notificationDistance = max(notificationDistance - 1, 1)
        saveSettings()
        
        let message = "提醒距離已調整為前\(notificationDistance)站"
        speakMessage(message, priority: .normal)
    }
    
    func setSpeechRate(_ rate: Float) {
        _speechRate = max(0.1, min(1.0, rate))
        saveSettings()
    }
    
    func setSpeechVolume(_ volume: Float) {
        _speechVolume = max(0.1, min(1.0, volume))
        saveSettings()
    }
    
    func setVoiceLanguage(_ language: String) {
        _voiceLanguage = language
        saveSettings()
    }
    
    // MARK: - 語音設定屬性
    
    var voiceLanguage: String { _voiceLanguage }
    var speechRate: Float { _speechRate }
    var speechVolume: Float { _speechVolume }
    
    // MARK: - 設定持久化
    
    private func saveSettings() {
        UserDefaults.standard.set(isAudioEnabled, forKey: "audioEnabled")
        UserDefaults.standard.set(notificationDistance, forKey: "notificationDistance")
        UserDefaults.standard.set(_speechRate, forKey: "speechRate")
        UserDefaults.standard.set(_speechVolume, forKey: "speechVolume")
        UserDefaults.standard.set(_voiceLanguage, forKey: "voiceLanguage")
    }
    
    private func loadSettings() {
        isAudioEnabled = UserDefaults.standard.bool(forKey: "audioEnabled")
        notificationDistance = UserDefaults.standard.integer(forKey: "notificationDistance")
        _speechRate = UserDefaults.standard.float(forKey: "speechRate")
        _speechVolume = UserDefaults.standard.float(forKey: "speechVolume")
        _voiceLanguage = UserDefaults.standard.string(forKey: "voiceLanguage") ?? "zh-TW"
        
        if notificationDistance == 0 { notificationDistance = 2 }
        if _speechRate == 0 { _speechRate = 0.5 }
        if _speechVolume == 0 { _speechVolume = 1.0 }
    }
    
    // MARK: - 重置通知狀態
    
    func resetNotificationStatus() {
        // 清理播報歷史
        lastAnnouncementTime = nil
        lastAnnouncementContent = nil
        pendingSpeechQueue.removeAll()
        notificationHistory.removeAll()
        
        // 重置目的地通知狀態
        hasNotifiedApproaching = false
        hasNotifiedArrival = false
        isSettingDestination = false
        
        // 停止當前播報
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        
        print("🔄 [Audio] 已重置音頻通知狀態")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        speechSynthesizer.stopSpeaking(at: .immediate)
        UIApplication.shared.endReceivingRemoteControlEvents()
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension AudioNotificationService: AVSpeechSynthesizerDelegate {
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("🎤 [Audio] 開始播報: \(utterance.speechString)")
        isSpeaking = true
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("✅ [Audio] 播報完成: \(utterance.speechString)")
        isSpeaking = false
        
        // 處理待播報隊列
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.processNextSpeechInQueue()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("🛑 [Audio] 播報被取消: \(utterance.speechString)")
        isSpeaking = false
        
        // 處理待播報隊列
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.processNextSpeechInQueue()
        }
    }
    
    private func processNextSpeechInQueue() {
        guard !pendingSpeechQueue.isEmpty, !isSpeaking, !speechSynthesizer.isSpeaking else {
            return
        }
        
        let nextMessage = pendingSpeechQueue.removeFirst()
        
        // 再次檢查是否可以播報（避免過時的隊列項目）
        if canAnnounce(nextMessage) {
            print("🎤 [Audio] 播報隊列中的下一個: \(nextMessage)")
            performSpeech(nextMessage, priority: .normal)
        }
    }
}

// MARK: - 語音優先級枚舉

private enum SpeechPriority {
    case normal, high, urgent
}
