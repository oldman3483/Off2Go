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
import CoreLocation

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
    private let minimumAnnouncementInterval: TimeInterval = 5.0
    private var isSpeaking: Bool = false
    
    // 目的地設定狀態
    private var destinationRoute: String?
    private var destinationStop: String?
    private var hasNotifiedApproaching = false
    private var hasNotifiedArrival = false
    
    // 位置追蹤
    private var locationTrackingTimer: Timer?
    private var lastKnownLocation: CLLocation?
    private var isTrackingActive = false
    
    override init() {
        super.init()
        setupAudioSession()
        setupHeadphoneDetection()
        setupRemoteControl()
        setupSpeechSynthesizerDelegate()
        loadSettings()
    }
    
    // MARK: - 語音播報核心方法
    
    private func speakMessage(_ message: String, priority: SpeechPriority = .normal) {
        // 檢查基本條件
        guard isAudioEnabled && (isHeadphonesConnected || allowSpeakerOutput()) else {
            print("🔇 [Audio] 播報條件不滿足")
            return
        }
        
        // 檢查是否可以播報
        guard canAnnounce(message) else {
            return
        }
        
        print("🎤 [Audio] 準備播報: \(message)")
        
        // 根據優先級處理
        switch priority {
        case .urgent:
            // 緊急情況：立即停止當前播報
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.stopSpeaking(at: .immediate)
            }
            performSpeech(message, priority: priority)
            
        case .high:
            // 高優先級：停止當前播報後執行
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.stopSpeaking(at: .word)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.performSpeech(message, priority: priority)
                }
            } else {
                performSpeech(message, priority: priority)
            }
            
        case .normal:
            // 普通優先級：如果正在播報則跳過
            if !speechSynthesizer.isSpeaking {
                performSpeech(message, priority: priority)
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
    
    // 檢查是否可以播報
    private func canAnnounce(_ content: String) -> Bool {
        let now = Date()
        
        // 檢查是否正在播報
        if isSpeaking || speechSynthesizer.isSpeaking {
            print("🔇 [Audio] 正在播報中，跳過: \(content)")
            return false
        }
        
        // 檢查重複內容和時間間隔
        if let lastContent = lastAnnouncementContent,
           lastContent == content,
           let lastTime = lastAnnouncementTime,
           now.timeIntervalSince(lastTime) < minimumAnnouncementInterval {
            print("🔇 [Audio] 重複內容且時間間隔過短，跳過: \(content)")
            return false
        }
        
        return true
    }
    
    // 更新播報記錄
    private func updateAnnouncementHistory(_ content: String) {
        lastAnnouncementTime = Date()
        lastAnnouncementContent = content
        isSpeaking = true
    }
    
    // MARK: - 目的地設定與追蹤
    
    /// 設定目的地並自動開始位置追蹤
    func setDestination(_ routeName: String, stopName: String) {
        print("🎯 [Audio] 設定目的地: \(routeName) - \(stopName)")
        
        // 防止重複設定
        if destinationRoute == routeName && destinationStop == stopName {
            print("🎯 [Audio] 目的地未變更，跳過設定")
            return
        }
        
        destinationRoute = routeName
        destinationStop = stopName
        targetStopName = stopName
        currentDestination = routeName.isEmpty ? stopName : "\(routeName) - \(stopName)"
        
        // 重置通知狀態
        hasNotifiedApproaching = false
        hasNotifiedArrival = false
        
        // 自動開始位置追蹤
        startLocationTracking()
        
        // 語音提醒
        let message = "目的地已設定為\(stopName)，將在接近時提醒您"
        speakMessage(message, priority: .high)
        
        // 更新媒體控制中心
        updateNowPlayingInfo(with: "追蹤中")
        
        print("✅ [Audio] 目的地設定完成，開始追蹤")
    }
    
    /// 清除目的地並停止追蹤
    func clearDestination() {
        print("🗑️ [Audio] 清除目的地")
        
        // 檢查是否真的有目的地需要清除
        let hadDestination = destinationRoute != nil || destinationStop != nil
        
        destinationRoute = nil
        destinationStop = nil
        targetStopName = nil
        currentDestination = nil
        hasNotifiedApproaching = false
        hasNotifiedArrival = false
        
        // 停止位置追蹤
        stopLocationTracking()
        
        // 只有在真的有目的地時才語音提醒
        if hadDestination {
            let message = "目的地已取消"
            speakMessage(message, priority: .normal)
            print("🔊 [Audio] 播報目的地取消訊息")
        } else {
            print("ℹ️ [Audio] 沒有目的地需要取消，跳過語音播報")
        }
        
        // 更新媒體控制中心
        updateNowPlayingInfo(with: "待機中")
        
        print("✅ [Audio] 已清除目的地並停止追蹤")
    }
    
    // MARK: - 位置追蹤管理
    
    private func startLocationTracking() {
        // 檢查位置權限
        let locationService = LocationService.shared
        guard locationService.hasLocationPermission else {
            print("⚠️ [Audio] 需要位置權限才能開始追蹤")
            return
        }
        
        // 停止現有追蹤
        stopLocationTracking()
        
        // 開始位置更新
        locationService.startUpdatingLocation()
        
        // 開始定期檢查位置
        locationTrackingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkLocationForDestination()
        }
        
        isTrackingActive = true
        print("📍 [Audio] 已開始位置追蹤")
    }
    
    private func stopLocationTracking() {
        locationTrackingTimer?.invalidate()
        locationTrackingTimer = nil
        isTrackingActive = false
        
        // 停止位置更新
        LocationService.shared.stopUpdatingLocation()
        
        print("🛑 [Audio] 已停止位置追蹤")
    }
    
    private func checkLocationForDestination() {
        guard let targetStop = destinationStop,
              let userLocation = LocationService.shared.currentLocation else {
            return
        }
        
        lastKnownLocation = userLocation
        
        // 這裡需要獲取目標站點的座標進行距離計算
        // 由於簡化版本，我們假設已經有了站點座標
        // 實際使用時需要傳入完整的站點資訊
        
        print("📍 [Audio] 檢查位置：用戶位置 \(userLocation.coordinate.latitude), \(userLocation.coordinate.longitude)")
    }
    
    /// 外部調用：檢查是否接近目的地站點
    func checkDestinationProximity(currentStops: [BusStop.Stop], userLocation: CLLocation) {
        guard isTrackingActive,
              let targetStop = destinationStop else {
            return
        }
        
        // 找到目的地站點
        guard let destinationStopData = currentStops.first(where: { $0.StopName.Zh_tw.contains(targetStop) }) else {
            return
        }
        
        let stopLocation = CLLocation(
            latitude: destinationStopData.StopPosition.PositionLat,
            longitude: destinationStopData.StopPosition.PositionLon
        )
        
        let distance = userLocation.distance(from: stopLocation)
        
        print("📏 [Audio] 距離目的地 \(Int(distance)) 公尺")
        
        // 根據距離提供不同級別的提醒
        if distance <= 100 && !hasNotifiedArrival {
            // 100公尺內：已到達提醒
            announceArrivalAtDestination()
            hasNotifiedArrival = true
        } else if distance <= 300 && !hasNotifiedApproaching {
            // 300公尺內：接近提醒
            announceApproachingDestination(distance: Int(distance))
            hasNotifiedApproaching = true
        }
    }
    
    // MARK: - 提醒方法
    
    private func announceApproachingDestination(distance: Int) {
        guard let targetStop = destinationStop else { return }
        let message = "提醒您，即將到達\(targetStop)，距離約\(distance)公尺，請準備下車"
        
        speakMessage(message, priority: .high)
        playNotificationSound()
        updateNowPlayingInfo(with: "即將到站")
        
        print("🔔 [Audio] 接近目的地提醒：\(distance)公尺")
    }
    
    private func announceArrivalAtDestination() {
        guard let targetStop = destinationStop else { return }
        let message = "\(targetStop)到了，請準備下車"
        
        speakMessage(message, priority: .urgent)
        playNotificationSound()
        updateNowPlayingInfo(with: "已到達")
        
        print("🎯 [Audio] 已到達目的地提醒")
    }
    
    func announceStationInfo(stopName: String, arrivalTime: String? = nil) {
        let baseMessage = "即將到達\(stopName)"
        var message = baseMessage
        
        if let time = arrivalTime, !time.isEmpty, time != baseMessage {
            message += "，\(time)"
        }
        
        speakMessage(message, priority: .normal)
    }
    
    // MARK: - 音頻設定控制
    
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
    
    // MARK: - 音頻會話設定
    
    private func setupAudioSession() {
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .allowBluetooth, .allowBluetoothA2DP]
            )
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                do {
                    try self.audioSession.setActive(true)
                    print("✅ [Audio] 音頻會話設定成功")
                } catch let error as NSError {
                    print("❌ [Audio] 音頻會話啟用失敗: \(error.localizedDescription)")
                    self.fallbackAudioSetup()
                }
            }
            
        } catch let error as NSError {
            print("❌ [Audio] 音頻會話設定失敗: \(error.localizedDescription)")
            fallbackAudioSetup()
        }
    }
    
    private func fallbackAudioSetup() {
        do {
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            print("✅ [Audio] 使用備用音頻設定成功")
        } catch {
            print("❌ [Audio] 備用音頻設定也失敗: \(error.localizedDescription)")
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
    
    private func setupSpeechSynthesizerDelegate() {
        speechSynthesizer.delegate = self
    }
    
    // MARK: - 媒體控制中心
    
    private func updateNowPlayingInfo(with status: String = "待機中") {
        var nowPlayingInfo = [String: Any]()
        
        if let destination = currentDestination {
            nowPlayingInfo[MPMediaItemPropertyTitle] = "Off2Go 到站提醒"
            nowPlayingInfo[MPMediaItemPropertyArtist] = destination
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = status
        } else {
            nowPlayingInfo[MPMediaItemPropertyTitle] = "Off2Go"
            nowPlayingInfo[MPMediaItemPropertyArtist] = "公車到站提醒"
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = status
        }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isTrackingActive ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // MARK: - 音效播放
    
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
    
    private func allowSpeakerOutput() -> Bool {
        return UserDefaults.standard.bool(forKey: "allowSpeakerOutput")
    }
    
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
    
    // MARK: - 重置和清理
    
    func resetNotificationStatus() {
        lastAnnouncementTime = nil
        lastAnnouncementContent = nil
        hasNotifiedApproaching = false
        hasNotifiedArrival = false
        
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        
        print("🔄 [Audio] 已重置音頻通知狀態")
    }
    
    deinit {
        stopLocationTracking()
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
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("🛑 [Audio] 播報被取消: \(utterance.speechString)")
        isSpeaking = false
    }
}

// MARK: - 語音優先級枚舉

private enum SpeechPriority {
    case normal, high, urgent
}
